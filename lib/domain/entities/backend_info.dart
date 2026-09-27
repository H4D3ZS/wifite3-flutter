// domain/entities/backend_info.dart

/// Backend hardware capability domain entity.
class BackendInfoEntity {
  final String scanBackend;
  final bool scanAvailable;
  final String monitorBackend;
  final bool monitorAvailable;
  final bool supportsMonitor;
  final bool supportsCapture;
  final bool supportsInjection;

  const BackendInfoEntity({
    required this.scanBackend,
    required this.scanAvailable,
    required this.monitorBackend,
    required this.monitorAvailable,
    required this.supportsMonitor,
    required this.supportsCapture,
    required this.supportsInjection,
  });

  bool get dongleConnected => monitorAvailable;
}
