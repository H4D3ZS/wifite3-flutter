// presentation/screens/evil_twin_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/access_point.dart';
import '../../domain/usecases/execute_evil_twin_attack.dart';
import '../../theme.dart';
import '../viewmodels/evil_twin_viewmodel.dart';
import '../../screens/scanner_screen.dart'; // for GridPainter

class EvilTwinScreen extends StatefulWidget {
  final AccessPoint target;

  const EvilTwinScreen({super.key, required this.target});

  @override
  State<EvilTwinScreen> createState() => _EvilTwinScreenState();
}

class _EvilTwinScreenState extends State<EvilTwinScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EvilTwinViewModel>().startAttack(widget.target);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EvilTwinViewModel>(
      builder: (context, viewModel, child) {
        final progress = viewModel.progress;

        return Scaffold(
          appBar: AppBar(
            title: Text('[ FLUXION EVIL TWIN ] - ${widget.target.displaySsid}'),
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
              Positioned.fill(child: CustomPaint(painter: GridPainter())),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;

                    return Padding(
                      padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildStatusCard(widget.target, progress, viewModel.capturedKey, isMobile),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.terminal, color: HackerTheme.secondary, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'EVIL_TWIN_CONSOLE >>',
                                style: TextStyle(
                                  color: HackerTheme.secondary.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
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
                                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
                              ),
                              child: ListView.builder(
                                itemCount: viewModel.logs.length,
                                reverse: true,
                                itemBuilder: (context, index) {
                                  final log = viewModel.logs[index];
                                  final isKey = log.contains('CRITICAL') || log.contains('PASSPHRASE');
                                  final isError = log.contains('ERROR') || log.contains('TERMINATED');

                                  Color textColor = HackerTheme.textMuted;
                                  if (isKey) textColor = HackerTheme.primary;
                                  if (isError) textColor = HackerTheme.error;
                                  if (index == 0) textColor = HackerTheme.textMain;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                                    child: Text(
                                      log,
                                      style: TextStyle(
                                        fontSize: isMobile ? 12 : 14,
                                        color: textColor,
                                        fontWeight: isKey ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: viewModel.isRunning ? HackerTheme.error : HackerTheme.primary,
                              foregroundColor: HackerTheme.background,
                              padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 20),
                            ),
                            icon: Icon(viewModel.isRunning ? Icons.stop : Icons.play_arrow),
                            onPressed: () {
                              if (viewModel.isRunning) {
                                viewModel.stopAttack();
                              } else {
                                viewModel.startAttack(widget.target);
                              }
                            },
                            label: Text(viewModel.isRunning ? 'TERMINATE ATTACK' : 'RESTART ATTACK'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(AccessPoint target, EvilTwinProgress? progress, String? capturedKey, bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: HackerTheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: capturedKey != null ? HackerTheme.primary : HackerTheme.primaryGlow, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: capturedKey != null ? HackerTheme.primaryGlow : HackerTheme.primaryGlow.withValues(alpha: 0.4),
            blurRadius: 12,
            spreadRadius: -2,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PHASE: ${progress?.phase.name.toUpperCase() ?? "INITIALIZING"}',
                style: TextStyle(
                  color: HackerTheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 14 : 16,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: HackerTheme.secondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: HackerTheme.secondary),
                ),
                child: Text(
                  'ROGUE AP ACTIVE',
                  style: TextStyle(color: HackerTheme.secondary, fontSize: isMobile ? 10 : 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (capturedKey != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: HackerTheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: HackerTheme.primary, width: 2),
              ),
              child: Column(
                children: [
                  const Text('KEY CAPTURED!', style: TextStyle(color: HackerTheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  SelectableText(
                    capturedKey,
                    style: const TextStyle(color: HackerTheme.textMain, fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 2),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              'Target AP: ${target.bssid} (CH ${target.channel})',
              style: TextStyle(color: HackerTheme.textMain, fontSize: isMobile ? 13 : 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Captive Portal: http://10.254.254.1 (Generic WPA/WPA2 Portal)',
              style: TextStyle(color: HackerTheme.textMuted, fontSize: isMobile ? 12 : 14),
            ),
          ],
        ],
      ),
    );
  }
}
