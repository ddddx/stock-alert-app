import 'package:flutter/material.dart';

MaterialApp buildTestApp(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      useMaterial3: false,
      splashFactory: InkRipple.splashFactory,
    ),
    home: Scaffold(body: child),
  );
}
