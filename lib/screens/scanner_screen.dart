import 'package:flutter/material.dart';
import '../native_bridge.dart';
import '../theme.dart';
import 'target_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _isScanning = false;
  List<ScanResult> _results = [];
  BackendInfo? _backendInfo;

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  Future<void> _initScanner() async {
    _backendInfo = await NativeBridge.getBackendInfo();
    setState(() {});
    
    NativeBridge.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        _results = results;
        // Sort by RSSI (strongest first)
        _results.sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    });
    
    _toggleScan();
  }

  Future<void> _toggleScan() async {
    if (_isScanning) {
      await NativeBridge.stopScan();
    } else {
      await NativeBridge.startScan();
    }
    if (!mounted) return;
    setState(() {
      _isScanning = !_isScanning;
    });
  }

  @override
  void dispose() {
    NativeBridge.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('[ W I F I T E 3 ]'),
        actions: [
          IconButton(
            icon: Icon(
              _backendInfo?.dongleConnected == true ? Icons.usb : Icons.usb_off,
              color: _backendInfo?.dongleConnected == true ? HackerTheme.primary : HackerTheme.error,
            ),
            tooltip: _backendInfo?.dongleConnected == true ? 'Dongle Connected' : 'Connect Dongle',
            onPressed: () async {
              if (_backendInfo?.dongleConnected == true) {
                await NativeBridge.disconnectDongle();
              } else {
                await NativeBridge.connectDongle();
              }
              final newInfo = await NativeBridge.getBackendInfo();
              if (mounted) {
                setState(() {
                  _backendInfo = newInfo;
                });
              }
            },
          )
        ],
      ),
      body: Column(
        children: [
          _buildStatusHeader(),
          Expanded(
            child: _results.isEmpty 
              ? const Center(child: Text('WAITING FOR TARGETS...', style: TextStyle(color: HackerTheme.textMuted)))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final target = _results[index];
                    return _buildTargetCard(context, target);
                  },
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _isScanning ? HackerTheme.error : HackerTheme.primary,
        onPressed: _toggleScan,
        child: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
      ),
    );
  }

  Widget _buildStatusHeader() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: HackerTheme.surface,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('> SCAN BACKEND: ${_backendInfo?.scanBackend ?? "WAITING"}'),
          Text('> MON BACKEND: ${_backendInfo?.monitorBackend ?? "WAITING"}'),
          Text('> STATUS: ${_isScanning ? "SCANNING..." : "IDLE"}', 
            style: TextStyle(color: _isScanning ? HackerTheme.primary : HackerTheme.textMuted)),
          Text('> TARGETS FOUND: ${_results.length}'),
        ],
      ),
    );
  }

  Widget _buildTargetCard(BuildContext context, ScanResult target) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TargetScreen(target: target),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _buildSignalIndicator(target.rssi),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target.ssid.isEmpty ? '<HIDDEN>' : target.ssid,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text('${target.bssid}  CH: ${target.channel}', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: HackerTheme.primary),
                ),
                child: Text(target.encryption),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignalIndicator(int rssi) {
    int bars = 0;
    if (rssi >= -60) {
      bars = 4;
    } else if (rssi >= -70) {
      bars = 3;
    } else if (rssi >= -80) {
      bars = 2;
    } else if (rssi >= -90) {
      bars = 1;
    }
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (index) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          width: 6,
          height: 12.0 + (index * 4),
          color: index < bars ? HackerTheme.primary : HackerTheme.surface,
        );
      }),
    );
  }
}
