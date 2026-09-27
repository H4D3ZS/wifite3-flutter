// WiFiBackend.h — Protocol both backends implement
//
// The Apple80211Backend handles scanning via the internal WiFi.
// The RTL8192EUBackend handles monitor mode, capture, and injection
// via the USB dongle. The MethodChannelHandler picks the right one.

#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A single scan result from either backend.
@interface WiFiScanResult : NSObject
@property (nonatomic, copy) NSString *bssid;
@property (nonatomic, copy) NSString *ssid;
@property (nonatomic, assign) int channel;
@property (nonatomic, assign) int rssi;
@property (nonatomic, copy) NSString *encryption;  // "OPEN", "WEP", "WPA", "WPA2", "WPA3"
@property (nonatomic, copy) NSString *frequency;   // "2.4 GHz" or "5 GHz"
@property (nonatomic, assign) BOOL wpsEnabled;
@property (nonatomic, copy, nullable) NSString *vendor;
- (NSDictionary *)toDictionary;
@end

/// Protocol both WiFi backends implement.
@protocol WiFiBackend <NSObject>

/// Whether this backend is currently available (internal WiFi = always,
/// dongle = only when plugged in).
- (BOOL)isAvailable;

/// Human-readable backend name for the UI.
- (NSString *)backendName;

// ---- Scanning (both backends) ----
- (void)startScanWithCallback:(void(^)(NSArray<WiFiScanResult*> *results))callback;
- (void)stopScan;

// ---- Capabilities ----
- (BOOL)supportsMonitorMode;
- (BOOL)supportsCapture;
- (BOOL)supportsInjection;

// ---- Monitor mode (RTL8192EU only) ----
- (BOOL)startMonitorMode;
- (BOOL)stopMonitorMode;
- (BOOL)setChannel:(int)channel;

// ---- Raw frame capture (RTL8192EU only) ----
- (void)startCaptureWithCallback:(void(^)(NSData *frame, int rssi, int channel))callback;
- (void)stopCapture;

// ---- Frame injection (RTL8192EU only) ----
- (BOOL)injectFrame:(NSData *)frameBytes;

// ---- Lifecycle ----
- (void)close;

@end

NS_ASSUME_NONNULL_END
