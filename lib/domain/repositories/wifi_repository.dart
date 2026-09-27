// domain/repositories/wifi_repository.dart
import 'dart:typed_data';
import '../entities/access_point.dart';
import '../entities/captured_frame.dart';
import '../entities/backend_info.dart';

/// Contract interface for Wi-Fi hardware operations, scanning, packet capture, and frame injection.
abstract class WifiRepository {
  /// Stream of discovered Access Points during active scan.
  Stream<List<AccessPoint>> get scanResults;

  /// Stream of raw captured 802.11 frames during active capture.
  Stream<CapturedFrameEntity> get capturedFrames;

  /// Start scanning using internal hardware.
  Future<bool> startScan();

  /// Stop scanning.
  Future<void> stopScan();

  /// Fetch current backend capability and hardware status.
  Future<BackendInfoEntity> getBackendInfo();

  /// Check if external Wi-Fi USB dongle is connected.
  Future<bool> isDongleConnected();

  /// Connect to plugged-in USB dongle.
  Future<bool> connectDongle();

  /// Disconnect USB dongle.
  Future<void> disconnectDongle();

  /// Start Monitor mode on target channel.
  Future<bool> startMonitorMode(int channel);

  /// Stop Monitor mode.
  Future<void> stopMonitorMode();

  /// Change radio channel.
  Future<bool> setChannel(int channel);

  /// Start raw packet capture.
  Future<bool> startCapture();

  /// Stop raw packet capture.
  Future<void> stopCapture();

  /// Inject raw 802.11 MPDU frame.
  Future<bool> injectFrame(Uint8List frameBytes);

  /// Clean up hardware resources.
  Future<void> dispose();
}
