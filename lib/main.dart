import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const BatteryAnalyzerApp());
}

class BatteryAnalyzerApp extends StatefulWidget {
  const BatteryAnalyzerApp({super.key});

  @override
  State<BatteryAnalyzerApp> createState() => _BatteryAnalyzerAppState();
}

class _BatteryAnalyzerAppState extends State<BatteryAnalyzerApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _onThemeModeChanged(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Battery Analyzer',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: HomeScreen(
        themeMode: _themeMode,
        onThemeModeChanged: _onThemeModeChanged,
      ),
    );
  }
}
