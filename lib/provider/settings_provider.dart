import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackflow/provider/background_provider.dart';

/// 設定のキー定数
class SettingsKeys {
  static const notifyDelivery = 'notify_delivery';
  static const notifyStatusChange = 'notify_status_change';
  static const updateInterval = 'update_interval';

  SettingsKeys._();
}

/// 設定操作用のProvider
final settingsProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

/// 配達完了通知のトグル状態
final notifyDeliveryProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(settingsProvider).valueOrNull;
  return prefs?.getBool(SettingsKeys.notifyDelivery) ?? true;
});

/// ステータス変更通知のトグル状態
final notifyStatusChangeProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(settingsProvider).valueOrNull;
  return prefs?.getBool(SettingsKeys.notifyStatusChange) ?? false;
});

/// 更新間隔
/// 利用可能な値: '15分', '30分', '1時間', '3時間'
final updateIntervalProvider = StateProvider<String>((ref) {
  final prefs = ref.watch(settingsProvider).valueOrNull;
  return prefs?.getString(SettingsKeys.updateInterval) ?? '30分';
});

/// 配達完了通知トグルを更新して保存
final setNotifyDeliveryProvider =
    Provider<void Function(bool)>((ref) {
  return (bool value) async {
    final prefs = await ref.read(settingsProvider.future);
    await prefs.setBool(SettingsKeys.notifyDelivery, value);
    ref.read(notifyDeliveryProvider.notifier).state = value;
  };
});

/// ステータス変更通知トグルを更新して保存
final setNotifyStatusChangeProvider =
    Provider<void Function(bool)>((ref) {
  return (bool value) async {
    final prefs = await ref.read(settingsProvider.future);
    await prefs.setBool(SettingsKeys.notifyStatusChange, value);
    ref.read(notifyStatusChangeProvider.notifier).state = value;
  };
});

/// 更新間隔を更新して保存
final setUpdateIntervalProvider =
    Provider<void Function(String)>((ref) {
  return (String value) async {
    final prefs = await ref.read(settingsProvider.future);
    await prefs.setString(SettingsKeys.updateInterval, value);
    ref.read(updateIntervalProvider.notifier).state = value;
    // バックグラウンドタスクの間隔も即時反映
    await updateBackgroundTaskInterval(value);
  };
});
