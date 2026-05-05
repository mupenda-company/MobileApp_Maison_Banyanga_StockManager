import 'package:flutter/material.dart';
import 'package:logis_agent/pages/splash.dart';
import 'package:logis_agent/theme/app_theme_controller.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: AppThemeController.instance.companyName,
          theme: AppThemeController.instance.theme,
          home: const Splash(),
        );
      },
    );
  }
}
