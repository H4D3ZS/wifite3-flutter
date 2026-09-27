import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../native_bridge.dart';
import '../theme.dart';
import 'target_screen.dart';
import '../viewmodels/scanner_viewmodel.dart';
import '../viewmodels/target_viewmodel.dart';

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ScannerViewModel>(
      builder: (context, viewModel, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('[ W I F I T E 3 ]'),
            actions: [
              IconButton(
                icon: Icon(
                  viewModel.backendInfo?.dongleConnected == true ? Icons.usb : Icons.usb_off,
                  color: viewModel.backendInfo?.dongleConnected == true ? HackerTheme.primary : HackerTheme.error,
                ),
                tooltip: viewModel.backendInfo?.dongleConnected == true ? 'Dongle Connected' : 'Connect Dongle',
                onPressed: () => viewModel.toggleDongle(),
              )
            ],
          ),
          body: Stack(
            children: [
              // Grid Background
              Positioned.fill(
                child: CustomPaint(
                  painter: GridPainter(),
                ),
              ),
              Column(
                children: [
                  _buildStatusHeader(viewModel),
                  const SizedBox(height: 8),
                  Expanded(
                    child: viewModel.results.isEmpty 
                      ? _buildScanningIndicator(viewModel.isScanning)
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: viewModel.results.length,
                          itemBuilder: (context, index) {
                            final target = viewModel.results[index];
                            return _buildTargetCard(context, target, index);
                          },
                        ),
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: viewModel.isScanning ? HackerTheme.error : HackerTheme.primary,
            onPressed: () => viewModel.toggleScan(),
            child: Icon(viewModel.isScanning ? Icons.stop : Icons.radar, size: 28),
          ),
        );
      },
    );
  }

  Widget _buildScanningIndicator(bool isScanning) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isScanning ? Icons.radar : Icons.wifi_find,
            size: 64,
            color: isScanning ? HackerTheme.primary : HackerTheme.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            isScanning ? 'SCANNING FREQUENCIES...' : 'SYSTEM IDLE',
            style: TextStyle(
              color: isScanning ? HackerTheme.primary : HackerTheme.textMuted,
              fontSize: 18,
              letterSpacing: 2,
              shadows: isScanning ? [const Shadow(color: HackerTheme.primaryGlow, blurRadius: 10)] : [],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusHeader(ScannerViewModel viewModel) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HackerTheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HackerTheme.primaryGlow, width: 1.5),
        boxShadow: const [
          BoxShadow(color: HackerTheme.primaryGlow, blurRadius: 15, spreadRadius: -5),
        ],
      ),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('SCAN_DRV: ${viewModel.backendInfo?.scanBackend ?? "WAIT"}', style: const TextStyle(fontSize: 12, color: HackerTheme.secondary)),
              Text('MON_DRV: ${viewModel.backendInfo?.monitorBackend ?? "WAIT"}', style: const TextStyle(fontSize: 12, color: HackerTheme.secondary)),
            ],
          ),
          const Divider(color: HackerTheme.borderDim, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('SYS_STATUS: ${viewModel.isScanning ? "ACTIVE" : "STANDBY"}', 
                style: TextStyle(color: viewModel.isScanning ? HackerTheme.primary : HackerTheme.textMuted, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('TGT_COUNT: ${viewModel.results.length}', style: const TextStyle(color: HackerTheme.textMain, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetCard(BuildContext context, ScanResult target, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 100).clamp(0, 500)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Card(
        elevation: 4,
        shadowColor: HackerTheme.primaryGlow,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => ChangeNotifierProvider(
                  create: (_) => TargetViewModel(target),
                  child: const TargetScreen(),
                ),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [HackerTheme.surface, HackerTheme.surface.withValues(alpha: 0.5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildSignalIndicator(target.rssi),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        target.ssid.isEmpty ? '<HIDDEN_SSID>' : target.ssid,
                        style: TextStyle(
                          fontWeight: FontWeight.bold, 
                          fontSize: 18,
                          color: HackerTheme.textMain,
                          shadows: [Shadow(color: HackerTheme.primaryGlow.withValues(alpha: 0.5), blurRadius: 5)],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.router, size: 14, color: HackerTheme.secondary),
                          const SizedBox(width: 4),
                          Text(target.bssid, style: const TextStyle(fontSize: 13, color: HackerTheme.secondary)),
                          const Spacer(),
                          Text('CH: ${target.channel.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 13, color: HackerTheme.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: target.encryption.contains('WPA') ? HackerTheme.borderDim : HackerTheme.error.withValues(alpha: 0.2),
                    border: Border.all(color: target.encryption.contains('WPA') ? HackerTheme.primary : HackerTheme.error),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    target.encryption,
                    style: TextStyle(
                      fontSize: 12, 
                      fontWeight: FontWeight.bold,
                      color: target.encryption.contains('WPA') ? HackerTheme.primary : HackerTheme.error,
                    ),
                  ),
                ),
              ],
            ),
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
    
    return SizedBox(
      height: 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (index) {
          final active = index < bars;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 8,
            height: 8.0 + (index * 5),
            decoration: BoxDecoration(
              color: active ? HackerTheme.primary : HackerTheme.borderDim,
              borderRadius: BorderRadius.circular(2),
              boxShadow: active ? [const BoxShadow(color: HackerTheme.primaryGlow, blurRadius: 4)] : [],
            ),
          );
        }),
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = HackerTheme.borderDim.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;
      
    const double step = 30.0;
    
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
