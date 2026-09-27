// native_bridge.dart — Dart side of the WiFi method channel
//
// Talks to MethodChannelHandler.mm on iOS. Scanning uses the internal
// WiFi (Apple80211) and works immediately. Monitor mode, capture, and
// injection require a plugged-in RTL8192EU dongle.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

/// A single WiFi network discovered by scanning.
class ScanResult {
  final String bssid;
  final String ssid;
  final int channel;
  final int rssi;
  final String encryption;
  final String frequency;
  final bool wpsEnabled;
  final String? vendor;

  ScanResult({
    required this.bssid,
    required this.ssid,
    required this.channel,
    required this.rssi,
    required this.encryption,
    required this.frequency,
    required this.wpsEnabled,
    this.vendor,
  });

  factory ScanResult.fromMap(Map<dynamic, dynamic> map) {
    return ScanResult(
      bssid: map['bssid'] ?? '',
      ssid: map['ssid'] ?? '',
      channel: map['channel'] ?? 0,
      rssi: map['rssi'] ?? -100,
      encryption: map['encryption'] ?? 'OPEN',
      frequency: map['frequency'] ?? '2.4 GHz',
      wpsEnabled: map['wps'] ?? false,
      vendor: map['vendor'],
    );
  }
}

/// A raw 802.11 frame captured in monitor mode.
class CapturedFrame {
  final Uint8List frameData;
  final int rssi;
  final int channel;

  CapturedFrame({
    required this.frameData,
    required this.rssi,
    required this.channel,
  });
}

/// Backend capability info.
class BackendInfo {
  final String scanBackend;
  final bool scanAvailable;
  final String monitorBackend;
  final bool monitorAvailable;
  final bool supportsMonitor;
  final bool supportsCapture;
  final bool supportsInjection;

  BackendInfo({
    required this.scanBackend,
    required this.scanAvailable,
    required this.monitorBackend,
    required this.monitorAvailable,
    required this.supportsMonitor,
    required this.supportsCapture,
    required this.supportsInjection,
  });

  factory BackendInfo.fromMap(Map<dynamic, dynamic> map) {
    return BackendInfo(
      scanBackend: map['scanBackend'] ?? 'Unknown',
      scanAvailable: map['scanAvailable'] ?? false,
      monitorBackend: map['monitorBackend'] ?? 'None',
      monitorAvailable: map['monitorAvailable'] ?? false,
      supportsMonitor: map['supportsMonitor'] ?? false,
      supportsCapture: map['supportsCapture'] ?? false,
      supportsInjection: map['supportsInjection'] ?? false,
    );
  }

  bool get dongleConnected => monitorAvailable;
}

/// The bridge to native WiFi backends.
///
/// Scanning uses the iPhone's internal WiFi (Apple80211) and works without
/// any hardware. Monitor mode, raw capture, and frame injection require
/// a plugged-in RTL8192EU USB adapter.
class NativeBridge {
  static const _channel = MethodChannel('com.wifiteapp/wifi');

  // Scan result stream
  static final _scanController = StreamController<List<ScanResult>>.broadcast();
  static Stream<List<ScanResult>> get scanResults => _scanController.stream;

  // Capture frame stream
  static final _captureController = StreamController<CapturedFrame>.broadcast();
  static Stream<CapturedFrame> get capturedFrames => _captureController.stream;

  /// Initialize the bridge. Call once from main().
  static void init() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// Handle callbacks from native → Dart (scan results, captured frames).
  static Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onScanResults':
        final List<dynamic> rawList = call.arguments;
        final results = rawList
            .map((m) => ScanResult.fromMap(m as Map<dynamic, dynamic>))
            .toList();
        _scanController.add(results);
        break;

      case 'onCapturedFrame':
        final map = call.arguments as Map<dynamic, dynamic>;
        final frameBase64 = map['frame'] as String;
        final frame = CapturedFrame(
          frameData: Uint8List.fromList(base64Decode(frameBase64)),
          rssi: map['rssi'] as int,
          channel: map['channel'] as int,
        );
        _captureController.add(frame);
        break;
    }
  }

  // ---- Scanning (internal WiFi, always works) ----

  /// Start scanning for networks. Results arrive via [scanResults] stream.
  static Future<bool> startScan() async {
    final result = await _channel.invokeMethod<bool>('startScan');
    return result ?? false;
  }

  /// Stop scanning.
  static Future<void> stopScan() async {
    await _channel.invokeMethod('stopScan');
  }

  // ---- Backend info ----

  /// Query what backends are available and their capabilities.
  static Future<BackendInfo> getBackendInfo() async {
    final map = await _channel.invokeMethod<Map>('getBackendInfo');
    return BackendInfo.fromMap(map ?? {});
  }

  /// Check if a USB dongle is connected.
  static Future<bool> isDongleConnected() async {
    final result = await _channel.invokeMethod<bool>('isDongleConnected');
    return result ?? false;
  }

  // ---- Dongle lifecycle ----

  /// Attempt to connect to a plugged-in RTL8192EU dongle.
  static Future<bool> connectDongle() async {
    final result = await _channel.invokeMethod<bool>('connectDongle');
    return result ?? false;
  }

  /// Disconnect from the dongle.
  static Future<void> disconnectDongle() async {
    await _channel.invokeMethod('disconnectDongle');
  }

  // ---- Monitor mode (requires dongle) ----

  /// Enter monitor mode on the USB adapter.
  static Future<bool> startMonitorMode() async {
    try {
      final result = await _channel.invokeMethod<bool>('startMonitorMode');
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'NO_DONGLE') return false;
      rethrow;
    }
  }

  /// Exit monitor mode.
  static Future<void> stopMonitorMode() async {
    await _channel.invokeMethod('stopMonitorMode');
  }

  /// Tune to a specific channel (1-14 for 2.4 GHz).
  static Future<bool> setChannel(int channel) async {
    final result = await _channel.invokeMethod<bool>('setChannel', channel);
    return result ?? false;
  }

  // ---- Capture (requires dongle + monitor mode) ----

  /// Start capturing raw 802.11 frames. Frames arrive via
  /// [capturedFrames] stream.
  static Future<bool> startCapture() async {
    try {
      final result = await _channel.invokeMethod<bool>('startCapture');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Stop capturing.
  static Future<void> stopCapture() async {
    await _channel.invokeMethod('stopCapture');
  }

  // ---- Injection (requires dongle + authorization) ----

  /// Inject a raw 802.11 frame. The frame bytes should be a complete
  /// MPDU (the TX descriptor is built by the native driver).
  ///
  /// This method must only be called after ScopeGateService.authorize()
  /// per the build plan's safety contract.
  static Future<bool> injectFrame(Uint8List frameBytes) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'injectFrame',
        frameBytes,
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Clean up all backends.
  static Future<void> dispose() async {
    await _channel.invokeMethod('dispose');
    _scanController.close();
    _captureController.close();
  }
}
