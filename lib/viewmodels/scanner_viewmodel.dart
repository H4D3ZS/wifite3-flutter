import 'dart:async';
import 'package:flutter/material.dart';
import '../native_bridge.dart';

class ScannerViewModel extends ChangeNotifier {
  bool _isScanning = false;
  List<ScanResult> _results = [];
  BackendInfo? _backendInfo;
  StreamSubscription? _scanSub;

  bool get isScanning => _isScanning;
  List<ScanResult> get results => _results;
  BackendInfo? get backendInfo => _backendInfo;

  ScannerViewModel() {
    _initScanner();
  }

  Future<void> _initScanner() async {
    _backendInfo = await NativeBridge.getBackendInfo();
    notifyListeners();
    
    _scanSub = NativeBridge.scanResults.listen((results) {
      _results = results;
      _results.sort((a, b) => b.rssi.compareTo(a.rssi));
      notifyListeners();
    });
    
    toggleScan();
  }

  Future<void> toggleScan() async {
    if (_isScanning) {
      await NativeBridge.stopScan();
    } else {
      await NativeBridge.startScan();
    }
    _isScanning = !_isScanning;
    notifyListeners();
  }

  Future<void> toggleDongle() async {
    if (_backendInfo?.dongleConnected == true) {
      await NativeBridge.disconnectDongle();
    } else {
      await NativeBridge.connectDongle();
    }
    _backendInfo = await NativeBridge.getBackendInfo();
    notifyListeners();
  }

  @override
  void dispose() {
    NativeBridge.stopScan();
    _scanSub?.cancel();
    super.dispose();
  }
}
