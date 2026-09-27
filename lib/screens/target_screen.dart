import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../domain/entities/access_point.dart';
import '../data/repositories/wifi_repository_impl.dart';
import '../presentation/screens/evil_twin_screen.dart';
import '../presentation/viewmodels/evil_twin_viewmodel.dart';
import '../theme.dart';
import '../viewmodels/target_viewmodel.dart';
import 'scanner_screen.dart'; // for GridPainter

class TargetScreen extends StatelessWidget {
  const TargetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TargetViewModel>(
      builder: (context, viewModel, child) {
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (viewModel.errorMessage != null) {
            _showError(context, viewModel.errorMessage!);
            viewModel.clearError();
          }
        });

        return Scaffold(
          appBar: AppBar(
            title: Text(viewModel.displaySsid),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(2.0),
              child: Container(
                color: HackerTheme.primary,
                height: 2.0,
                width: double.infinity,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [BoxShadow(color: HackerTheme.primaryGlow, blurRadius: 8)],
                  ),
                ),
              ),
            ),
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: GridPainter(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTargetInfo(viewModel),
                    const SizedBox(height: 20),
                    _buildControls(viewModel),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Icon(Icons.terminal, color: HackerTheme.secondary, size: 20),
                        const SizedBox(width: 8),
                        Text('SYS_LOG >>', style: TextStyle(color: HackerTheme.secondary.withValues(alpha: 0.8), fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        const Spacer(),
                        if (viewModel.handshakeCaptured)
                           const Icon(Icons.vpn_key, color: HackerTheme.primary, size: 20),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: HackerTheme.borderDim, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black54, blurRadius: 10),
                          ],
                        ),
                        child: ListView.builder(
                          itemCount: viewModel.logs.length,
                          reverse: true,
                          itemBuilder: (context, index) {
                            final log = viewModel.logs[index];
                            final isError = log.contains('ERROR') || log.contains('FAILED');
                            final isSuccess = log.contains('SUCCESS') || log.contains('CAPTURED');
                            
                            Color textColor = HackerTheme.textMuted;
                            if (isError) textColor = HackerTheme.error;
                            if (isSuccess) textColor = HackerTheme.primary;
                            if (index == 0) textColor = HackerTheme.textMain; // latest log is bright
                            
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Text(
                                log,
                                style: TextStyle(fontSize: 13, color: textColor),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: HackerTheme.background),
            const SizedBox(width: 12),
            Expanded(child: Text(msg, style: const TextStyle(color: HackerTheme.background, fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: HackerTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildTargetInfo(TargetViewModel viewModel) {
    return Container(
      decoration: BoxDecoration(
        color: HackerTheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HackerTheme.primaryGlow, width: 1.5),
        boxShadow: const [BoxShadow(color: HackerTheme.primaryGlow, blurRadius: 10, spreadRadius: -5)],
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          _buildInfoRow('BSSID', viewModel.target.bssid, Icons.router),
          const Divider(color: HackerTheme.borderDim, height: 24),
          _buildInfoRow('CHANNEL', '${viewModel.target.channel} (${viewModel.target.frequency})', Icons.settings_input_antenna),
          const Divider(color: HackerTheme.borderDim, height: 24),
          _buildInfoRow('SECURITY', '${viewModel.target.encryption}${viewModel.target.wpsEnabled ? " + WPS" : ""}', Icons.security),
          const Divider(color: HackerTheme.borderDim, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.cell_wifi, color: HackerTheme.secondary, size: 18),
                  const SizedBox(width: 8),
                  const Text('CLIENTS', style: TextStyle(color: HackerTheme.secondary, fontSize: 14)),
                ],
              ),
              Text(viewModel.clients.length.toString(), style: const TextStyle(color: HackerTheme.primary, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: HackerTheme.secondary, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: HackerTheme.secondary, fontSize: 14)),
          ],
        ),
        Text(value, style: const TextStyle(color: HackerTheme.textMain, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildControls(TargetViewModel viewModel) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: viewModel.monitorActive ? HackerTheme.surface : HackerTheme.primary,
                  foregroundColor: viewModel.monitorActive ? HackerTheme.primary : HackerTheme.background,
                  side: BorderSide(color: HackerTheme.primary, width: viewModel.monitorActive ? 2 : 0),
                ),
                icon: Icon(viewModel.monitorActive ? Icons.stop_circle_outlined : Icons.play_circle_fill),
                onPressed: () => viewModel.toggleMonitorMode(),
                label: Text(viewModel.monitorActive ? 'STOP MON' : 'START MON'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                 style: ElevatedButton.styleFrom(
                  backgroundColor: viewModel.captureActive ? HackerTheme.surface : HackerTheme.secondary,
                  foregroundColor: viewModel.captureActive ? HackerTheme.secondary : HackerTheme.background,
                  side: BorderSide(color: HackerTheme.secondary, width: viewModel.captureActive ? 2 : 0),
                ),
                icon: Icon(viewModel.captureActive ? Icons.stop_circle_outlined : Icons.camera_alt),
                onPressed: viewModel.monitorActive ? () => viewModel.toggleCapture() : null,
                label: Text(viewModel.captureActive ? 'STOP CAP' : 'START CAP'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.flash_on),
                onPressed: viewModel.monitorActive ? () => viewModel.injectDeauth() : null,
                label: const Text('DEAUTH [CLIENT]'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: HackerTheme.secondary,
                  side: BorderSide(color: viewModel.monitorActive ? HackerTheme.secondary : HackerTheme.borderDim, width: 2),
                ),
                icon: const Icon(Icons.cell_tower),
                onPressed: viewModel.monitorActive ? () => viewModel.injectPmkidAttack() : null,
                label: const Text('PMKID [ROUTER]'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HackerTheme.primary,
              foregroundColor: HackerTheme.background,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.security, size: 20),
            onPressed: () {
              final domainAp = AccessPoint(
                bssid: viewModel.target.bssid,
                ssid: viewModel.target.ssid,
                channel: viewModel.target.channel,
                rssi: viewModel.target.rssi,
                encryption: viewModel.target.encryption,
                frequency: viewModel.target.frequency,
                wpsEnabled: viewModel.target.wpsEnabled,
                vendor: viewModel.target.vendor,
              );

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider(
                    create: (_) => EvilTwinViewModel(WifiRepositoryImpl()),
                    child: EvilTwinScreen(target: domainAp),
                  ),
                ),
              );
            },
            label: const Text('LAUNCH FLUXION EVIL TWIN CAPTIVE PORTAL', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
        ),
      ],
    );
  }
}
