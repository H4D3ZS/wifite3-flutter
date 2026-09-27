// data/repositories/wifi_repository_impl.dart
import 'dart:async';
import 'dart:typed_data';

import '../../domain/entities/access_point.dart';
import '../../domain/entities/backend_info.dart';
import '../../domain/entities/captured_frame.dart';
import '../../domain/repositories/wifi_repository.dart';
import '../../native_bridge.dart';

/// Implementation of [WifiRepository] connecting to [NativeBridge].
class WifiRepositoryImpl implements WifiRepository {
  final _scanController = StreamController<List<AccessPoint>>.broadcast();
  final _captureController = StreamController<CapturedFrameEntity>.broadcast();

  StreamSubscription? _scanSub;
  StreamSubscription? _captureSub;

  WifiRepositoryImpl() {
    _scanSub = NativeBridge.scanResults.listen((results) {
      final domainPoints = results.map((r) => AccessPoint(
        bssid: r.bssid,
        ssid: r.ssid,
        channel: r.channel,
        rssi: r.rssi,
        encryption: r.encryption,
        frequency: r.frequency,
        wpsEnabled: r.wpsEnabled,
        vendor: r.vendor,
      )).toList();
      _scanController.add(domainPoints);
    });

    _captureSub = NativeBridge.capturedFrames.listen((frame) {
      _captureController.add(CapturedFrameEntity(
        frameData: frame.frameData,
        rssi: frame.rssi,
        channel: frame.channel,
      ));
    });
  }

  @override
  Stream<List<AccessPoint>> get scanResults => _scanController.stream;

  @override
  Stream<CapturedFrameEntity> get capturedFrames => _captureController.stream;

  @override
  Future<bool> startScan() => NativeBridge.startScan();

  @override
  Future<void> stopScan() => NativeBridge.stopScan();

  @override
  Future<BackendInfoEntity> getBackendInfo() async {
    final info = await NativeBridge.getBackendInfo();
    return BackendInfoEntity(
      scanBackend: info.scanBackend,
      scanAvailable: info.scanAvailable,
      monitorBackend: info.monitorBackend,
      monitorAvailable: info.monitorAvailable,
      supportsMonitor: info.supportsMonitor,
      supportsCapture: info.supportsCapture,
      supportsInjection: info.supportsInjection,
    );
  }

  @override
  Future<bool> isDongleConnected() => NativeBridge.isDongleConnected();

  @override
  Future<bool> connectDongle() => NativeBridge.connectDongle();

  @override
  Future<void> disconnectDongle() => NativeBridge.disconnectDongle();

  @override
  Future<bool> startMonitorMode(int channel) async {
    final ok = await NativeBridge.startMonitorMode();
    if (ok) {
      await NativeBridge.setChannel(channel);
    }
    return ok;
  }

  @override
  Future<void> stopMonitorMode() => NativeBridge.stopMonitorMode();

  @override
  Future<bool> setChannel(int channel) => NativeBridge.setChannel(channel);

  @override
  Future<bool> startCapture() => NativeBridge.startCapture();

  @override
  Future<void> stopCapture() => NativeBridge.stopCapture();

  @override
  Future<bool> injectFrame(Uint8List frameBytes) => NativeBridge.injectFrame(frameBytes);

  @override
  Future<void> dispose() async {
    await _scanSub?.cancel();
    await _captureSub?.cancel();
    await _scanController.close();
    await _captureController.close();
  }
}
