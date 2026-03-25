import 'package:flutter/material.dart';

import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';

class StockAlertApp extends StatelessWidget {
  const StockAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '股票异动雷达',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const AppShell(),
    );
  }
}
