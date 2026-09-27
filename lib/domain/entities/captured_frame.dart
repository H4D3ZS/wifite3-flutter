// domain/entities/captured_frame.dart
import 'dart:typed_data';

/// Domain entity representing a captured raw 802.11 packet frame.
class CapturedFrameEntity {
  final Uint8List frameData;
  final int rssi;
  final int channel;
  final DateTime timestamp;

  CapturedFrameEntity({
    required this.frameData,
    required this.rssi,
    required this.channel,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
