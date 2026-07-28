import 'package:flutter/material.dart';
import 'package:trackflow/core/theme/app_theme.dart';
import 'package:trackflow/presentation/router/app_router.dart';

class TrackFlowApp extends StatelessWidget {
  const TrackFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TrackFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
