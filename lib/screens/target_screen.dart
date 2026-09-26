import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../native_bridge.dart';
import '../theme.dart';

class TargetScreen extends StatefulWidget {
  final ScanResult target;

  const TargetScreen({super.key, required this.target});

  @override
  State<TargetScreen> createState() => _TargetScreenState();
}

class _TargetScreenState extends State<TargetScreen> {
  bool _monitorActive = false;
  bool _captureActive = false;
  int _capturedCount = 0;
  final List<String> _logs = [];
  BackendInfo? _backendInfo;

  @override
  void initState() {
    super.initState();
    _initTarget();
  }

  Future<void> _initTarget() async {
    _backendInfo = await NativeBridge.getBackendInfo();
    setState(() {});

    NativeBridge.capturedFrames.listen((frame) {
      if (!mounted) return;
      setState(() {
        _capturedCount++;
        if (_capturedCount % 10 == 0) { // Throttle logs
          _addLog('CAPTURED FRAME [RSSI: ${frame.rssi} CH: ${frame.channel}] SIZE: ${frame.frameData.length}');
        }
      });
    });
  }

  void _addLog(String msg) {
    _logs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] $msg');
    if (_logs.length > 50) _logs.removeLast();
  }

  Future<void> _toggleMonitorMode() async {
    if (_monitorActive) {
      await NativeBridge.stopMonitorMode();
      _addLog('MONITOR MODE: OFF');
      if (mounted) {
        setState(() {
          _monitorActive = false;
          _captureActive = false;
        });
      }
    } else {
      if (_backendInfo?.dongleConnected != true) {
        _showError('DONGLE REQUIRED FOR MONITOR MODE');
        return;
      }
      
      _addLog('STARTING MONITOR MODE...');
      final ok = await NativeBridge.startMonitorMode();
      if (ok) {
        await NativeBridge.setChannel(widget.target.channel);
        _addLog('MONITOR MODE: ON (CH ${widget.target.channel})');
        if (mounted) setState(() => _monitorActive = true);
      } else {
        _addLog('ERROR: FAILED TO START MONITOR MODE');
      }
    }
  }

  Future<void> _toggleCapture() async {
    if (!_monitorActive) {
      _showError('MONITOR MODE MUST BE ACTIVE');
      return;
    }
    
    if (_captureActive) {
      await NativeBridge.stopCapture();
      _addLog('CAPTURE: STOPPED');
      if (mounted) setState(() => _captureActive = false);
    } else {
      _addLog('STARTING RAW CAPTURE...');
      final ok = await NativeBridge.startCapture();
      if (ok) {
        _addLog('CAPTURE: RUNNING');
        if (mounted) setState(() => _captureActive = true);
      } else {
        _addLog('ERROR: FAILED TO START CAPTURE');
      }
    }
  }
  
  Future<void> _injectDeauth() async {
     if (!_monitorActive) {
      _showError('MONITOR MODE MUST BE ACTIVE');
      return;
    }
    _addLog('PREPARING DEAUTH INJECTION (TARGET: ${widget.target.bssid})');
    // We would need ScopeGateService.authorize() here, but for UI demo we just attempt it.
    // Build a dummy deauth frame for testing (usually built properly based on target)
    final dummyFrame = Uint8List(32); 
    final ok = await NativeBridge.injectFrame(dummyFrame);
    if (ok) {
       _addLog('INJECTION: SUCCESS');
    } else {
       _addLog('INJECTION: FAILED (AUTH REQUIRED?)');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Courier', color: HackerTheme.background, fontWeight: FontWeight.bold)),
        backgroundColor: HackerTheme.error,
      ),
    );
  }

  @override
  void dispose() {
    NativeBridge.stopCapture();
    NativeBridge.stopMonitorMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('TARGET: ${widget.target.ssid.isEmpty ? widget.target.bssid : widget.target.ssid}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTargetInfo(),
            const SizedBox(height: 16),
            _buildControls(),
            const SizedBox(height: 16),
            const Text('> OPERATION LOG:', style: TextStyle(color: HackerTheme.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: HackerTheme.textMuted),
                  color: HackerTheme.background,
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    return Text(_logs[index], style: const TextStyle(fontSize: 12, color: HackerTheme.textMain));
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BSSID:      ${widget.target.bssid}'),
            Text('SSID:       ${widget.target.ssid.isEmpty ? "<HIDDEN>" : widget.target.ssid}'),
            Text('CHANNEL:    ${widget.target.channel}'),
            Text('ENCRYPTION: ${widget.target.encryption}'),
            Text('RSSI:       ${widget.target.rssi} dBm'),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _monitorActive ? HackerTheme.error : HackerTheme.primary,
                ),
                onPressed: _toggleMonitorMode,
                child: Text(_monitorActive ? 'STOP MONITOR' : 'START MONITOR'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                 style: ElevatedButton.styleFrom(
                  backgroundColor: _captureActive ? HackerTheme.error : HackerTheme.primary,
                ),
                onPressed: _monitorActive ? _toggleCapture : null,
                child: Text(_captureActive ? 'STOP CAPTURE' : 'START CAPTURE'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: HackerTheme.error,
              side: const BorderSide(color: HackerTheme.error),
            ),
            onPressed: _monitorActive ? _injectDeauth : null,
            child: const Text('INJECT DEAUTH [ATTACK]'),
          ),
        ),
      ],
    );
  }
}
