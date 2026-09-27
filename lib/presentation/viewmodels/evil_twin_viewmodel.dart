// presentation/viewmodels/evil_twin_viewmodel.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/entities/access_point.dart';
import '../../domain/repositories/wifi_repository.dart';
import '../../domain/usecases/execute_evil_twin_attack.dart';

class EvilTwinViewModel extends ChangeNotifier {
  final WifiRepository repository;
  late final ExecuteEvilTwinAttack _executeEvilTwin;

  bool _isRunning = false;
  EvilTwinProgress? _progress;
  final List<String> _logs = [];
  String? _capturedKey;
  StreamSubscription? _sub;

  bool get isRunning => _isRunning;
  EvilTwinProgress? get progress => _progress;
  List<String> get logs => _logs;
  String? get capturedKey => _capturedKey;

  EvilTwinViewModel(this.repository) {
    _executeEvilTwin = ExecuteEvilTwinAttack(repository);
  }

  void startAttack(AccessPoint target) {
    if (_isRunning) return;

    _isRunning = true;
    _capturedKey = null;
    _logs.clear();
    _addLog('FLUXION EVIL TWIN ATTACK LAUNCHED ON [${target.displaySsid}]');
    notifyListeners();

    _sub = _executeEvilTwin(target).listen((prog) {
      _progress = prog;
      _addLog(prog.statusLog);
      if (prog.capturedPassword != null) {
        _capturedKey = prog.capturedPassword;
        _addLog('*** CRITICAL: PASSPHRASE CAPTURED: $_capturedKey ***');
      }
      notifyListeners();
    });
  }

  void stopAttack() {
    _executeEvilTwin.stop();
    _sub?.cancel();
    _isRunning = false;
    _addLog('EVIL TWIN ATTACK TERMINATED');
    notifyListeners();
  }

  void _addLog(String msg) {
    _logs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] $msg');
    if (_logs.length > 100) _logs.removeLast();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
