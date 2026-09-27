// domain/entities/access_point.dart

/// Represents a Wi-Fi Access Point entity in the domain.
class AccessPoint {
  final String bssid;
  final String ssid;
  final int channel;
  final int rssi;
  final String encryption;
  final String frequency;
  final bool wpsEnabled;
  final String? vendor;
  final String? decloakedSsid;

  const AccessPoint({
    required this.bssid,
    required this.ssid,
    required this.channel,
    required this.rssi,
    required this.encryption,
    required this.frequency,
    required this.wpsEnabled,
    this.vendor,
    this.decloakedSsid,
  });

  /// Displays either the decloaked SSID, given SSID, or hidden indicator.
  String get displaySsid {
    if (decloakedSsid != null && decloakedSsid!.isNotEmpty) {
      return decloakedSsid!;
    }
    if (ssid.isEmpty || ssid.contains('<HIDDEN')) {
      return '<HIDDEN_SSID>';
    }
    return ssid;
  }

  bool get isHidden => ssid.isEmpty || ssid.contains('<HIDDEN');

  AccessPoint copyWith({
    String? bssid,
    String? ssid,
    int? channel,
    int? rssi,
    String? encryption,
    String? frequency,
    bool? wpsEnabled,
    String? vendor,
    String? decloakedSsid,
  }) {
    return AccessPoint(
      bssid: bssid ?? this.bssid,
      ssid: ssid ?? this.ssid,
      channel: channel ?? this.channel,
      rssi: rssi ?? this.rssi,
      encryption: encryption ?? this.encryption,
      frequency: frequency ?? this.frequency,
      wpsEnabled: wpsEnabled ?? this.wpsEnabled,
      vendor: vendor ?? this.vendor,
      decloakedSsid: decloakedSsid ?? this.decloakedSsid,
    );
  }
}
