import 'package:flutter/material.dart';

import 'screens/scan_screen.dart';

void main() {
  runApp(const JkBmsApp());
}

/// JK-BMS BLE Test Application.
///
/// Provides UI screens to scan, connect, and monitor JK-BMS devices
/// over Bluetooth Low Energy.
class JkBmsApp extends StatelessWidget {
  const JkBmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JK-BMS Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1B5E20),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        cardTheme: const CardThemeData(
          color: Color(0xFF161B22),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: Color(0xFF30363D)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1117),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const ScanScreen(),
    );
  }
}
