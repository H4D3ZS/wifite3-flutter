import 'package:flutter/material.dart';

import 'native_bridge.dart';
import 'theme.dart';
import 'screens/scanner_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NativeBridge.init();
  runApp(const WifiteApp());
}

class WifiteApp extends StatelessWidget {
  const WifiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wifite 3',
      debugShowCheckedModeBanner: false,
      theme: HackerTheme.themeData,
      home: const ScannerScreen(),
    );
  }
}
