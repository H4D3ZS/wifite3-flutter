// MethodChannelHandler.mm — Dart ↔ Native bridge
//
// Routes Flutter method channel calls to the appropriate backend:
//   - Scanning → Apple80211Backend (internal WiFi, always available)
//   - Monitor/Capture/Inject → RTL8192EUBackend (USB dongle, if plugged in)
//
// This is the single native entry point registered in AppDelegate.

#import <Flutter/Flutter.h>
#import "WiFiBackend.h"

// Forward-declare the backends
@class Apple80211Backend;

// ============================================================
// MethodChannelHandler
// ============================================================

@interface MethodChannelHandler : NSObject
@property (nonatomic, strong) id<WiFiBackend> scanBackend;      // Apple80211
@property (nonatomic, strong, nullable) id<WiFiBackend> monitorBackend;  // RTL8192EU (if dongle present)
@property (nonatomic, strong) FlutterMethodChannel *channel;
@property (nonatomic, strong, nullable) FlutterEventSink captureEventSink;
@end

@implementation MethodChannelHandler

- (instancetype)initWithBinaryMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    self = [super init];
    if (self) {
        // Initialize the scan backend (internal WiFi — always available)
        self.scanBackend = [[NSClassFromString(@"Apple80211Backend") alloc] init];

        // The monitor backend (RTL8192EU) is initialized on-demand
        // when the user requests monitor mode and a dongle is detected.
        self.monitorBackend = nil;

        // Register the method channel
        self.channel = [FlutterMethodChannel
            methodChannelWithName:@"com.wifiteapp/wifi"
                  binaryMessenger:messenger];

        __weak typeof(self) weakSelf = self;
        [self.channel setMethodCallHandler:^(FlutterMethodCall *call,
                                              FlutterResult result) {
            [weakSelf handleMethodCall:call result:result];
        }];
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *method = call.method;

    // ---- Scanning (uses internal WiFi) ----

    if ([method isEqualToString:@"startScan"]) {
        [self.scanBackend startScanWithCallback:^(NSArray<WiFiScanResult*> *results) {
            NSMutableArray *dicts = [NSMutableArray new];
            for (WiFiScanResult *r in results) {
                [dicts addObject:[r toDictionary]];
            }
            [self.channel invokeMethod:@"onScanResults" arguments:dicts];
        }];
        result(@YES);
        return;
    }

    if ([method isEqualToString:@"stopScan"]) {
        [self.scanBackend stopScan];
        result(@YES);
        return;
    }

    // ---- Dongle status ----

    if ([method isEqualToString:@"isDongleConnected"]) {
        result(@(self.monitorBackend != nil && [self.monitorBackend isAvailable]));
        return;
    }

    if ([method isEqualToString:@"getBackendInfo"]) {
        result(@{
            @"scanBackend": [self.scanBackend backendName],
            @"scanAvailable": @([self.scanBackend isAvailable]),
            @"monitorBackend": self.monitorBackend
                ? [self.monitorBackend backendName] : @"None",
            @"monitorAvailable": @(self.monitorBackend != nil
                && [self.monitorBackend isAvailable]),
            @"supportsMonitor": @(self.monitorBackend != nil
                && [self.monitorBackend supportsMonitorMode]),
            @"supportsCapture": @(self.monitorBackend != nil
                && [self.monitorBackend supportsCapture]),
            @"supportsInjection": @(self.monitorBackend != nil
                && [self.monitorBackend supportsInjection]),
        });
        return;
    }

    // ---- Monitor mode (requires dongle) ----

    if ([method isEqualToString:@"startMonitorMode"]) {
        if (!self.monitorBackend || ![self.monitorBackend supportsMonitorMode]) {
            result([FlutterError errorWithCode:@"NO_DONGLE"
                                       message:@"No USB adapter connected. "
                                                "Plug in an RTL8192EU dongle "
                                                "for monitor mode."
                                       details:nil]);
            return;
        }
        BOOL ok = [self.monitorBackend startMonitorMode];
        result(@(ok));
        return;
    }

    if ([method isEqualToString:@"stopMonitorMode"]) {
        if (self.monitorBackend) {
            [self.monitorBackend stopMonitorMode];
        }
        result(@YES);
        return;
    }

    if ([method isEqualToString:@"setChannel"]) {
        int channel = [call.arguments intValue];
        id<WiFiBackend> backend = self.monitorBackend ?: self.scanBackend;
        result(@([backend setChannel:channel]));
        return;
    }

    // ---- Capture (requires dongle + monitor mode) ----

    if ([method isEqualToString:@"startCapture"]) {
        if (!self.monitorBackend || ![self.monitorBackend supportsCapture]) {
            result([FlutterError errorWithCode:@"NO_DONGLE"
                                       message:@"Capture requires USB adapter"
                                       details:nil]);
            return;
        }
        [self.monitorBackend startCaptureWithCallback:
            ^(NSData *frame, int rssi, int ch) {
                // Send raw frames to Dart via method channel invocation
                [self.channel invokeMethod:@"onCapturedFrame" arguments:@{
                    @"frame": [frame base64EncodedStringWithOptions:0],
                    @"rssi": @(rssi),
                    @"channel": @(ch),
                }];
            }
        ];
        result(@YES);
        return;
    }

    if ([method isEqualToString:@"stopCapture"]) {
        if (self.monitorBackend) {
            [self.monitorBackend stopCapture];
        }
        result(@YES);
        return;
    }

    // ---- Injection (requires dongle + ScopeGateService authorization) ----

    if ([method isEqualToString:@"injectFrame"]) {
        if (!self.monitorBackend || ![self.monitorBackend supportsInjection]) {
            result([FlutterError errorWithCode:@"NO_DONGLE"
                                       message:@"Injection requires USB adapter"
                                       details:nil]);
            return;
        }
        FlutterStandardTypedData *frameData = call.arguments;
        NSData *bytes = frameData.data;
        BOOL ok = [self.monitorBackend injectFrame:bytes];
        result(@(ok));
        return;
    }

    // ---- Connect dongle (called when user plugs in adapter) ----

    if ([method isEqualToString:@"connectDongle"]) {
        // Attempt to initialize the RTL8192EU backend
        // This is done lazily — only when the user actually needs it
        [self initMonitorBackend];
        BOOL connected = self.monitorBackend != nil
                       && [self.monitorBackend isAvailable];
        result(@(connected));
        return;
    }

    if ([method isEqualToString:@"disconnectDongle"]) {
        if (self.monitorBackend) {
            [self.monitorBackend close];
            self.monitorBackend = nil;
        }
        result(@YES);
        return;
    }

    // ---- Cleanup ----

    if ([method isEqualToString:@"dispose"]) {
        [self.scanBackend close];
        if (self.monitorBackend) {
            [self.monitorBackend close];
            self.monitorBackend = nil;
        }
        result(@YES);
        return;
    }

    result(FlutterMethodNotImplemented);
}

- (void)initMonitorBackend {
    // Try to load the RTL8192EU backend
    // The RTL8192EUBackend class wraps Rtl8192eudriver.h/mm and exposes
    // it through the WiFiBackend protocol.
    Class backendClass = NSClassFromString(@"RTL8192EUBackend");
    if (backendClass) {
        self.monitorBackend = [[backendClass alloc] init];
        if (![self.monitorBackend isAvailable]) {
            self.monitorBackend = nil;
            NSLog(@"[MethodChannel] RTL8192EU dongle not found on USB");
        } else {
            NSLog(@"[MethodChannel] RTL8192EU dongle connected");
        }
    }
}

@end

// ============================================================
// Registration helper — called from AppDelegate
// ============================================================

void RegisterMethodChannelHandler(NSObject<FlutterBinaryMessenger> *messenger) {
    // The handler retains itself via the method channel block.
    // ARC handles the lifecycle.
    (void)[[MethodChannelHandler alloc] initWithBinaryMessenger:messenger];
}
