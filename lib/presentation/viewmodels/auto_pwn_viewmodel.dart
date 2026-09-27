// presentation/viewmodels/auto_pwn_viewmodel.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/entities/access_point.dart';
import '../../domain/repositories/wifi_repository.dart';
import '../../domain/usecases/execute_auto_pwn.dart';

class AutoPwnViewModel extends ChangeNotifier {
  final WifiRepository repository;
  late final ExecuteAutoPwn _executeAutoPwn;

  bool _isRunning = false;
  AutoPwnProgress? _currentProgress;
  final List<String> _logs = [];
  StreamSubscription? _campaignSub;

  bool get isRunning => _isRunning;
  AutoPwnProgress? get currentProgress => _currentProgress;
  List<String> get logs => _logs;

  AutoPwnViewModel(this.repository) {
    _executeAutoPwn = ExecuteAutoPwn(repository);
  }

  void startCampaign(List<AccessPoint> targets) {
    if (_isRunning) return;

    _isRunning = true;
    _logs.clear();
    _addLog('AUTO-PWN CAMPAIGN LAUNCHED');
    notifyListeners();

    _campaignSub = _executeAutoPwn.runCampaign(targets).listen((progress) {
      _currentProgress = progress;
      _addLog(progress.statusLog);

      if (progress.phase == AutoPwnPhase.completed) {
        _isRunning = false;
      }
      notifyListeners();
    }, onError: (err) {
      _addLog('CAMPAIGN ERROR: $err');
      _isRunning = false;
      notifyListeners();
    });
  }

  void stopCampaign() {
    _campaignSub?.cancel();
    _isRunning = false;
    _addLog('CAMPAIGN ABORTED BY USER');
    notifyListeners();
  }

  void _addLog(String msg) {
    _logs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] $msg');
    if (_logs.length > 100) _logs.removeLast();
  }

  @override
  void dispose() {
    _campaignSub?.cancel();
    super.dispose();
  }
}
