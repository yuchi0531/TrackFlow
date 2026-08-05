import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trackflow/app.dart';
import 'package:trackflow/provider/background_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // バックグラウンドサービスを初期化してからアプリ起動
  // （完了前にプロセスkillされると定期タスクが登録されないためawaitする）
  try {
    await initBackgroundService();
  } catch (e) {
    debugPrint('Failed to initialize background service: $e');
  }

  // 通知チャンネルを事前作成（権限リクエストと独立）
  // 権限は設定画面のトグルでリクエストする
  try {
    await initNotificationChannels();
  } catch (e) {
    debugPrint('Failed to initialize notification channels: $e');
  }

  runApp(
    const ProviderScope(
      child: TrackFlowApp(),
    ),
  );
}
