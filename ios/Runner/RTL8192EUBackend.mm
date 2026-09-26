// RTL8192EUBackend.mm — Wraps Rtl8192eudriver (C++) into the WiFiBackend protocol
//
// This is the monitor-mode backend. It bridges the C++ RTL8192EUDriver
// class into Obj-C so the MethodChannelHandler can use it identically
// to the Apple80211Backend.

#import "WiFiBackend.h"
#import "Rtl8192eudriver.h"
#include <memory>

@interface RTL8192EUBackend : NSObject <WiFiBackend> {
    std::unique_ptr<RTL8192EUDriver> _driver;
    BOOL _monitorActive;
    BOOL _captureActive;
    int _currentChannel;
}
@end

@implementation RTL8192EUBackend

- (instancetype)init {
    self = [super init];
    if (self) {
        _driver = std::make_unique<RTL8192EUDriver>();
        _monitorActive = NO;
        _captureActive = NO;
        _currentChannel = 1;

        // Attempt to open the dongle on init
        if (!_driver->open()) {
            NSLog(@"[RTL8192EU] no dongle found on USB");
        } else {
            NSLog(@"[RTL8192EU] dongle opened, MAC=%s",
                  _driver->macAddress().c_str());

            // Load and upload the firmware blob
            NSString *fwPath = [[NSBundle mainBundle] pathForResource:@"rtl8192eufw" ofType:@"bin"];
            if (fwPath) {
                NSData *fwData = [NSData dataWithContentsOfFile:fwPath];
                if (fwData && fwData.length > 0) {
                    if (_driver->uploadFirmware((const uint8_t*)fwData.bytes, fwData.length)) {
                        NSLog(@"[RTL8192EU] firmware uploaded successfully");
                    } else {
                        NSLog(@"[RTL8192EU] firmware upload failed");
                    }
                }
            } else {
                NSLog(@"[RTL8192EU] firmware blob (rtl8192eufw.bin) not found in app bundle");
            }
        }
    }
    return self;
}

// ---- WiFiBackend protocol ----

- (BOOL)isAvailable {
    return _driver && _driver->isOpen();
}

- (NSString *)backendName {
    if (_driver && _driver->isOpen()) {
        return [NSString stringWithFormat:@"RTL8192EU (%s)",
                _driver->macAddress().c_str()];
    }
    return @"RTL8192EU (disconnected)";
}

- (BOOL)supportsMonitorMode { return YES; }
- (BOOL)supportsCapture     { return YES; }
- (BOOL)supportsInjection   { return YES; }

// ---- Scanning ----
// The dongle CAN scan (by hopping channels in monitor mode and parsing
// beacons), but we defer scanning to the Apple80211 backend since it's
// faster and doesn't require monitor mode. This scan implementation
// exists for completeness but the MethodChannelHandler routes scans
// to Apple80211Backend by default.

- (void)startScanWithCallback:(void(^)(NSArray<WiFiScanResult*> *))callback {
    // Dongle-based scanning would go here: hop channels, collect beacons,
    // parse SSIDs. For now, defer to Apple80211Backend.
    NSLog(@"[RTL8192EU] scan requested — defer to internal WiFi backend");
}

- (void)stopScan {
    // No-op when scanning is handled by Apple80211
}

// ---- Monitor mode ----

- (BOOL)startMonitorMode {
    if (!_driver || !_driver->isOpen()) return NO;
    if (_monitorActive) return YES;

    // The driver's setMonitorMode handles: power-on (if cold),
    // RCR configuration, RF path enable, TX unpause, CCK+OFDM enable
    BOOL ok = _driver->setMonitorMode(true);
    if (ok) {
        _monitorActive = YES;
        NSLog(@"[RTL8192EU] monitor mode ON");
    }
    return ok;
}

- (BOOL)stopMonitorMode {
    if (_captureActive) [self stopCapture];
    if (_driver && _driver->isOpen()) {
        _driver->setMonitorMode(false);
    }
    _monitorActive = NO;
    NSLog(@"[RTL8192EU] monitor mode OFF");
    return YES;
}

- (BOOL)setChannel:(int)channel {
    if (!_driver || !_driver->isOpen()) return NO;
    BOOL ok = _driver->setChannel(channel);
    if (ok) _currentChannel = channel;
    return ok;
}

// ---- Capture ----

- (void)startCaptureWithCallback:(void(^)(NSData *frame, int rssi, int channel))callback {
    if (!_driver || !_driver->isOpen() || !_monitorActive) return;
    if (_captureActive) return;
    _captureActive = YES;

    // The C++ driver's startCapture runs the bulk-IN read loop on a
    // background thread and calls the callback for each decoded frame.
    _driver->startCapture([callback, self](const RawFrame& raw) {
        if (!self->_captureActive) return;

        NSData *frameData = [NSData dataWithBytes:raw.data.data()
                                           length:raw.data.size()];
        // Dispatch to main thread for Flutter compatibility
        dispatch_async(dispatch_get_main_queue(), ^{
            if (callback) {
                callback(frameData, raw.rssi_dbm, raw.channel);
            }
        });
    });

    NSLog(@"[RTL8192EU] capture started on channel %d", _currentChannel);
}

- (void)stopCapture {
    if (_driver) {
        _driver->stopCapture();
    }
    _captureActive = NO;
    NSLog(@"[RTL8192EU] capture stopped");
}

// ---- Injection ----

- (BOOL)injectFrame:(NSData *)frameBytes {
    if (!_driver || !_driver->isOpen() || !_monitorActive) return NO;

    std::vector<uint8_t> bytes(
        static_cast<const uint8_t*>(frameBytes.bytes),
        static_cast<const uint8_t*>(frameBytes.bytes) + frameBytes.length
    );
    return _driver->injectFrame(bytes);
}

// ---- Lifecycle ----

- (void)close {
    [self stopCapture];
    if (_driver) {
        _driver->close();
    }
    _monitorActive = NO;
    NSLog(@"[RTL8192EU] closed");
}

- (void)dealloc {
    [self close];
}

@end
