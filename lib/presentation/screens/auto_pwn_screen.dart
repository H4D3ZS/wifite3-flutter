// presentation/screens/auto_pwn_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/access_point.dart';
import '../../domain/usecases/execute_auto_pwn.dart';
import '../../theme.dart';
import '../viewmodels/auto_pwn_viewmodel.dart';
import '../../screens/scanner_screen.dart'; // for GridPainter

class AutoPwnScreen extends StatefulWidget {
  final List<AccessPoint> targets;

  const AutoPwnScreen({super.key, required this.targets});

  @override
  State<AutoPwnScreen> createState() => _AutoPwnScreenState();
}

class _AutoPwnScreenState extends State<AutoPwnScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AutoPwnViewModel>().startCampaign(widget.targets);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoPwnViewModel>(
      builder: (context, viewModel, child) {
        final progress = viewModel.currentProgress;

        return Scaffold(
          appBar: AppBar(
            title: const Text('[ AUTO-PWN CAMPAIGN ]'),
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
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCampaignProgressCard(progress, viewModel.isRunning),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.terminal, color: HackerTheme.secondary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'CAMPAIGN_LOG >>',
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
                            final isSuccess = log.contains('SUCCESS') || log.contains('✓');
                            final isError = log.contains('ERROR') || log.contains('ABORTED');

                            Color textColor = HackerTheme.textMuted;
                            if (isSuccess) textColor = HackerTheme.primary;
                            if (isError) textColor = HackerTheme.error;
                            if (index == 0) textColor = HackerTheme.textMain;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Text(log, style: TextStyle(fontSize: 13, color: textColor)),
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
                      ),
                      icon: Icon(viewModel.isRunning ? Icons.stop : Icons.play_arrow),
                      onPressed: () {
                        if (viewModel.isRunning) {
                          viewModel.stopCampaign();
                        } else {
                          viewModel.startCampaign(widget.targets);
                        }
                      },
                      label: Text(viewModel.isRunning ? 'ABORT CAMPAIGN' : 'RESTART CAMPAIGN'),
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

  Widget _buildCampaignProgressCard(AutoPwnProgress? progress, bool isRunning) {
    final completed = progress?.completedTargets ?? 0;
    final total = progress?.totalTargets ?? widget.targets.length;
    final percent = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HackerTheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HackerTheme.primaryGlow, width: 1.5),
        boxShadow: const [BoxShadow(color: HackerTheme.primaryGlow, blurRadius: 10, spreadRadius: -5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PHASE: ${progress?.phase.name.toUpperCase() ?? "INITIALIZING"}',
                style: const TextStyle(color: HackerTheme.primary, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                '$completed / $total TARGETS',
                style: const TextStyle(color: HackerTheme.textMain, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: percent,
            backgroundColor: HackerTheme.borderDim,
            color: HackerTheme.primary,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          if (progress?.currentTarget != null) ...[
            Row(
              children: [
                const Icon(Icons.radar, color: HackerTheme.secondary, size: 16),
                const SizedBox(width: 6),
                Text(
                  'CURRENT TARGET: ${progress!.currentTarget!.displaySsid}',
                  style: const TextStyle(color: HackerTheme.secondary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
