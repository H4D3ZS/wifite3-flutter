import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'native_bridge.dart';
import 'theme.dart';
import 'screens/scanner_screen.dart';
import 'viewmodels/scanner_viewmodel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NativeBridge.init();
  runApp(const WifiteApp());
}

class WifiteApp extends StatelessWidget {
  const WifiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ScannerViewModel()),
      ],
      child: MaterialApp(
        title: 'Wifite 3',
        debugShowCheckedModeBanner: false,
        theme: HackerTheme.themeData,
        home: const ScannerScreen(),
      ),
    );
  }
}
