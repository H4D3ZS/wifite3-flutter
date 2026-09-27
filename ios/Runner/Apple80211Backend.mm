// Apple80211Backend.mm — Internal WiFi scanner via Apple's private framework
//
// On jailbroken iOS, Apple80211 gives us full scan results (BSSID, SSID,
// channel, RSSI, encryption) without any external hardware. This is the
// "app opens and works immediately" backend.
//
// The Apple80211 functions are loaded at runtime via dlopen/dlsym since
// the framework is private and not in the SDK headers.
//
// Capabilities: scan only. Monitor mode, capture, and injection return NO.

#import "WiFiBackend.h"
#import <dlfcn.h>
#import <objc/runtime.h>

// ============================================================
// WiFiScanResult implementation
// ============================================================

@implementation WiFiScanResult

- (NSDictionary *)toDictionary {
    return @{
        @"bssid": self.bssid ?: @"",
        @"ssid": self.ssid ?: @"",
        @"channel": @(self.channel),
        @"rssi": @(self.rssi),
        @"encryption": self.encryption ?: @"OPEN",
        @"frequency": self.frequency ?: @"2.4 GHz",
        @"wps": @(self.wpsEnabled),
        @"vendor": self.vendor ?: @"",
    };
}

@end

// ============================================================
// Apple80211 private framework function signatures
//
// These are loaded at runtime via dlsym. The signatures come from
// reverse-engineered private headers — they change between iOS
// versions, so version-check accordingly.
// ============================================================

typedef void* Apple80211Ref;

// Core lifecycle
typedef int (*Apple80211OpenFn)(Apple80211Ref *ref);
typedef int (*Apple80211CloseFn)(Apple80211Ref ref);
typedef int (*Apple80211BindToInterfaceFn)(Apple80211Ref ref, CFStringRef ifName);

// Scanning
typedef int (*Apple80211ScanFn)(Apple80211Ref ref, CFArrayRef *results, CFDictionaryRef params);

// Info query
typedef int (*Apple80211GetInfoCopyFn)(Apple80211Ref ref, CFDictionaryRef *info);
typedef int (*Apple80211CopyValueFn)(Apple80211Ref ref, int code, CFDictionaryRef params, void *result);

// ============================================================
// Apple80211Backend
// ============================================================

@interface Apple80211Backend : NSObject <WiFiBackend> {
    void *_apple80211Handle;
    Apple80211Ref _wifiRef;

    Apple80211OpenFn _openFn;
    Apple80211CloseFn _closeFn;
    Apple80211BindToInterfaceFn _bindFn;
    Apple80211ScanFn _scanFn;

    BOOL _loaded;
    BOOL _scanning;
    dispatch_queue_t _scanQueue;
}
@end

@implementation Apple80211Backend

- (instancetype)init {
    self = [super init];
    if (self) {
        _scanQueue = dispatch_queue_create("com.wifiteapp.apple80211.scan",
                                           DISPATCH_QUEUE_SERIAL);
        [self loadFramework];
    }
    return self;
}

- (void)loadFramework {
    // Load Apple80211.framework at runtime
    _apple80211Handle = dlopen(
        "/System/Library/PrivateFrameworks/Apple80211.framework/Apple80211",
        RTLD_LAZY
    );
    if (!_apple80211Handle) {
        NSLog(@"[Apple80211] dlopen failed: %s", dlerror());
        _loaded = NO;
        return;
    }

    _openFn = (Apple80211OpenFn)dlsym(_apple80211Handle, "Apple80211Open");
    _closeFn = (Apple80211CloseFn)dlsym(_apple80211Handle, "Apple80211Close");
    _bindFn = (Apple80211BindToInterfaceFn)dlsym(_apple80211Handle,
                                                  "Apple80211BindToInterface");
    _scanFn = (Apple80211ScanFn)dlsym(_apple80211Handle, "Apple80211Scan");

    if (!_openFn || !_closeFn || !_bindFn || !_scanFn) {
        NSLog(@"[Apple80211] missing symbols — framework API may have changed");
        _loaded = NO;
        return;
    }

    // Open a reference and bind to en0 (the WiFi interface on iOS)
    int rc = _openFn(&_wifiRef);
    if (rc != 0) {
        NSLog(@"[Apple80211] Open failed: %d", rc);
        _loaded = NO;
        return;
    }

    rc = _bindFn(_wifiRef, CFSTR("en0"));
    if (rc != 0) {
        NSLog(@"[Apple80211] BindToInterface(en0) failed: %d", rc);
        _closeFn(_wifiRef);
        _wifiRef = NULL;
        _loaded = NO;
        return;
    }

    _loaded = YES;
    NSLog(@"[Apple80211] framework loaded, bound to en0");
}

// ---- WiFiBackend protocol ----

- (BOOL)isAvailable {
    return _loaded;
}

- (NSString *)backendName {
    return @"Internal WiFi (Apple80211)";
}

- (BOOL)supportsMonitorMode { return NO; }
- (BOOL)supportsCapture     { return NO; }
- (BOOL)supportsInjection   { return NO; }

- (BOOL)startMonitorMode { return NO; }
- (BOOL)stopMonitorMode  { return NO; }
- (BOOL)setChannel:(int)channel { return NO; }
- (void)startCaptureWithCallback:(void(^)(NSData*, int, int))callback {}
- (void)stopCapture {}
- (BOOL)injectFrame:(NSData *)frameBytes { return NO; }

- (void)startScanWithCallback:(void(^)(NSArray<WiFiScanResult*> *))callback {
    if (!_loaded || _scanning) return;
    _scanning = YES;

    dispatch_async(_scanQueue, ^{
        while (self->_scanning) {
            NSArray<WiFiScanResult*> *results = [self performScan];
            if (results && callback) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    callback(results);
                });
            }
            // Scan interval — Apple80211Scan takes ~2-3s itself,
            // add a small gap to avoid hammering the radio.
            [NSThread sleepForTimeInterval:1.0];
        }
    });
}

- (void)stopScan {
    _scanning = NO;
}

- (NSArray<WiFiScanResult*> *)performScan {
    if (!_loaded || !_scanFn) return @[];

    // Build scan parameters — empty dict = scan all channels, all SSIDs
    CFDictionaryRef params = CFDictionaryCreate(
        kCFAllocatorDefault, NULL, NULL, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );

    CFArrayRef rawResults = NULL;
    int rc = _scanFn(_wifiRef, &rawResults, params);
    CFRelease(params);

    if (rc != 0 || !rawResults) {
        NSLog(@"[Apple80211] scan failed: %d", rc);
        return @[];
    }

    NSArray *scanArray = (__bridge_transfer NSArray *)rawResults;
    NSMutableArray<WiFiScanResult*> *results = [NSMutableArray new];

    for (NSDictionary *entry in scanArray) {
        WiFiScanResult *r = [WiFiScanResult new];

        // BSSID — stored as "BSSID" key, hex string "aa:bb:cc:dd:ee:ff"
        r.bssid = entry[@"BSSID"] ?: @"";

        // SSID — stored as NSData under "SSID_NAME" or "SSID"
        id ssidRaw = entry[@"SSID_NAME"] ?: entry[@"SSID"];
        if ([ssidRaw isKindOfClass:[NSData class]]) {
            r.ssid = [[NSString alloc] initWithData:ssidRaw
                                           encoding:NSUTF8StringEncoding] ?: @"";
        } else if ([ssidRaw isKindOfClass:[NSString class]]) {
            r.ssid = ssidRaw;
        } else {
            r.ssid = @"";
        }

        // Channel
        r.channel = [entry[@"CHANNEL"] intValue];

        // RSSI
        r.rssi = [entry[@"RSSI"] intValue];

        // Encryption — derive from AP_MODE / WPA_IE / RSN_IE presence
        r.encryption = [self parseEncryption:entry];
        
        // Frequency - Channels <= 14 are 2.4 GHz, Channels > 14 are 5 GHz (or 6 GHz)
        if (r.channel <= 14) {
            r.frequency = @"2.4 GHz";
        } else {
            r.frequency = @"5 GHz"; // Covers 5Ghz for simplicity
        }

        // WPS - Apple80211 returns "WPS_PROB_RESP_IE" if WPS is enabled
        r.wpsEnabled = (entry[@"WPS_PROB_RESP_IE"] != nil);

        [results addObject:r];
    }

    return results;
}

- (NSString *)parseEncryption:(NSDictionary *)entry {
    // Apple80211 scan results include WPA/RSN information elements.
    // The logic mirrors wifit3's WlanFrameParser encryption detection:
    //   RSN IE present → WPA2 (or WPA3 if SAE suite)
    //   WPA IE present → WPA
    //   Privacy bit only → WEP
    //   None → OPEN

    NSDictionary *rsnIE = entry[@"RSN_IE"];
    NSDictionary *wpaIE = entry[@"WPA_IE"];

    if (rsnIE) {
        // Check for SAE (WPA3) auth suite — OUI 00-0F-AC, type 8
        NSArray *authSuites = rsnIE[@"AUTH_SUITES"];
        if ([authSuites isKindOfClass:[NSArray class]]) {
            for (NSDictionary *suite in authSuites) {
                int type = [suite[@"TYPE"] intValue];
                if (type == 8) return @"WPA3";
            }
        }
        return @"WPA2";
    }
    if (wpaIE) return @"WPA";

    // Check AP_MODE for privacy bit
    int apMode = [entry[@"AP_MODE"] intValue];
    if (apMode & 0x10) return @"WEP";  // privacy bit

    return @"OPEN";
}

- (void)close {
    [self stopScan];
    if (_wifiRef && _closeFn) {
        _closeFn(_wifiRef);
        _wifiRef = NULL;
    }
    if (_apple80211Handle) {
        dlclose(_apple80211Handle);
        _apple80211Handle = NULL;
    }
    _loaded = NO;
}

- (void)dealloc {
    [self close];
}

@end
