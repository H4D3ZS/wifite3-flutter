import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class PcapWriter {
  final File file;
  late final RandomAccessFile _raf;
  bool _isOpen = false;

  PcapWriter(this.file);

  static Future<PcapWriter> create(String bssid) async {
    final dir = await getApplicationDocumentsDirectory();
    final safeBssid = bssid.replaceAll(':', '');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/capture_${safeBssid}_$timestamp.pcap');
    
    final writer = PcapWriter(file);
    await writer.open();
    return writer;
  }

  Future<void> open() async {
    _raf = await file.open(mode: FileMode.write);
    
    // PCAP Global Header (24 bytes)
    final header = ByteData(24);
    header.setUint32(0, 0xa1b2c3d4, Endian.little); // Magic Number
    header.setUint16(4, 2, Endian.little);          // Major Version
    header.setUint16(6, 4, Endian.little);          // Minor Version
    header.setInt32(8, 0, Endian.little);           // Reserved1
    header.setInt32(12, 0, Endian.little);          // Reserved2
    header.setUint32(16, 65535, Endian.little);     // SnapLen
    header.setUint32(20, 105, Endian.little);       // LinkType (105 = IEEE 802.11)

    await _raf.writeFrom(header.buffer.asUint8List());
    _isOpen = true;
  }

  Future<void> writePacket(Uint8List packetData) async {
    if (!_isOpen) return;
    
    final now = DateTime.now();
    final seconds = (now.millisecondsSinceEpoch / 1000).floor();
    final microseconds = (now.microsecondsSinceEpoch % 1000000);

    // PCAP Packet Header (16 bytes)
    final header = ByteData(16);
    header.setUint32(0, seconds, Endian.little);
    header.setUint32(4, microseconds, Endian.little);
    header.setUint32(8, packetData.length, Endian.little);
    header.setUint32(12, packetData.length, Endian.little);

    await _raf.writeFrom(header.buffer.asUint8List());
    await _raf.writeFrom(packetData);
  }

  Future<void> close() async {
    if (_isOpen) {
      await _raf.close();
      _isOpen = false;
    }
  }
}
