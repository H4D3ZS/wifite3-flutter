import 'dart:typed_data';

class PacketParser {
  /// Extract a client MAC address if this is a data frame involving the target BSSID
  static String? extractClientMac(Uint8List frame, String targetBssid) {
    if (frame.length < 24) return null;
    
    final fc = frame[0];
    final type = (fc >> 2) & 0x03;

    // Check if Data frame
    if (type == 2) {
      final addr1 = _macString(frame, 4);
      final addr2 = _macString(frame, 10);
      final addr3 = _macString(frame, 16);

      if (addr1 == targetBssid && _isUnicast(addr2)) return addr2;
      if (addr2 == targetBssid && _isUnicast(addr1)) return addr1;
      if (addr3 == targetBssid && _isUnicast(addr1)) return addr1;
      if (addr3 == targetBssid && _isUnicast(addr2)) return addr2;
    }
    return null;
  }
  
  /// Check if the frame contains EAPOL (WPA handshake) payload
  static bool hasEapol(Uint8List frame) {
    // Look for EAPOL EtherType (88 8E)
    for (int i = 0; i < frame.length - 1; i++) {
       if (frame[i] == 0x88 && frame[i+1] == 0x8E) return true;
    }
    return false;
  }

  /// Craft a basic 802.11 Authentication frame (Open System)
  static Uint8List craftAuth(String bssid, String myMac) {
    final frame = Uint8List(30);
    // Frame Control: Subtype 11 (Auth), Type 0 (Mgmt)
    frame[0] = 0xB0; // 10110000
    frame[1] = 0x00;
    
    final dst = _macBytes(bssid);
    final src = _macBytes(myMac);
    
    // Addr1 (Destination / BSSID)
    frame.setRange(4, 10, dst);
    // Addr2 (Source / My MAC)
    frame.setRange(10, 16, src);
    // Addr3 (BSSID)
    frame.setRange(16, 22, dst);
    
    // Sequence Control
    frame[22] = 0x00;
    frame[23] = 0x00;
    
    // Auth Algorithm (0 = Open System)
    frame[24] = 0x00;
    frame[25] = 0x00;
    // Auth Seq (1)
    frame[26] = 0x01;
    frame[27] = 0x00;
    // Status Code (0 = Success)
    frame[28] = 0x00;
    frame[29] = 0x00;
    
    return frame;
  }

  /// Craft a basic 802.11 Association Request frame
  static Uint8List craftAssocReq(String bssid, String myMac, String ssid) {
    final ssidBytes = ssid.codeUnits;
    final frame = Uint8List(30 + ssidBytes.length);
    // Frame Control: Subtype 0 (Assoc Req), Type 0 (Mgmt)
    frame[0] = 0x00;
    frame[1] = 0x00;
    
    final dst = _macBytes(bssid);
    final src = _macBytes(myMac);
    
    // Addr1 (Destination / BSSID)
    frame.setRange(4, 10, dst);
    // Addr2 (Source / My MAC)
    frame.setRange(10, 16, src);
    // Addr3 (BSSID)
    frame.setRange(16, 22, dst);
    
    // Sequence Control
    frame[22] = 0x00;
    frame[23] = 0x00;
    
    // Capability Info (default typical)
    frame[24] = 0x11;
    frame[25] = 0x04;
    // Listen Interval (1)
    frame[26] = 0x01;
    frame[27] = 0x00;
    
    // SSID Tag (Tag Number 0)
    frame[28] = 0x00;
    // Tag Length
    frame[29] = ssidBytes.length;
    // Tag Data
    for (int i = 0; i < ssidBytes.length; i++) {
      frame[30 + i] = ssidBytes[i];
    }
    
    return frame;
  }

  /// Craft a basic 802.11 Deauthentication frame
  static Uint8List craftDeauth(String bssid, String clientMac) {
    final frame = Uint8List(38);
    // Frame Control: Subtype 12 (Deauth), Type 0 (Mgmt)
    frame[0] = 0xC0; // 11000000
    frame[1] = 0x00;
    // Duration
    frame[2] = 0x00;
    frame[3] = 0x00;
    
    final dst = _macBytes(clientMac);
    final src = _macBytes(bssid);
    final bss = _macBytes(bssid);
    
    // Addr1 (Destination)
    frame.setRange(4, 10, dst);
    // Addr2 (Source)
    frame.setRange(10, 16, src);
    // Addr3 (BSSID)
    frame.setRange(16, 22, bss);
    
    // Sequence Control
    frame[22] = 0x00;
    frame[23] = 0x00;
    
    // Reason Code 7 (Class 3 frame received from nonassociated STA)
    frame[24] = 0x07;
    frame[25] = 0x00;
    
    return frame;
  }

  static String _macString(Uint8List data, int offset) {
    if (offset + 6 > data.length) return "";
    return List.generate(6, (i) => data[offset + i].toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
  }
  
  static Uint8List _macBytes(String mac) {
    final parts = mac.split(':');
    final bytes = Uint8List(6);
    if (parts.length == 6) {
      for (int i = 0; i < 6; i++) {
        bytes[i] = int.parse(parts[i], radix: 16);
      }
    }
    return bytes;
  }

  static bool _isUnicast(String mac) {
    if (mac.isEmpty || mac == "FF:FF:FF:FF:FF:FF") return false;
    try {
      final b1 = int.parse(mac.substring(0, 2), radix: 16);
      return (b1 & 1) == 0;
    } catch(e) {
      return false;
    }
  }
}
