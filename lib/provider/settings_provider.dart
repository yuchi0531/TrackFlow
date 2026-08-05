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

/// SharedPreferences の読み書きを一元管理するNotifier。
///
/// `state` を更新（setBool / setString 後に再代入）することで、
/// このproviderをwatchしている各設定providerが再ビルドされ、
/// 保存済みの値が確実にUIへ反映される。
class SettingsController extends AsyncNotifier<SharedPreferences> {
  @override
  Future<SharedPreferences> build() => SharedPreferences.getInstance();

  /// SharedPreferences インスタンスを取得（解決済みなら即、未解決なら待機）
  Future<SharedPreferences> _getPrefs() async {
    final current = state;
    if (current.hasValue && current.value != null) {
      return current.value!;
    }
    return await future;
  }

  /// 配達完了通知トグルを更新して保存
  Future<void> setNotifyDelivery(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(SettingsKeys.notifyDelivery, value);
    // stateを再代入してwatch側へ通知
    state = AsyncValue.data(prefs);
  }

  /// ステータス変更通知トグルを更新して保存
  Future<void> setNotifyStatusChange(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(SettingsKeys.notifyStatusChange, value);
    state = AsyncValue.data(prefs);
  }

  /// 更新間隔を更新して保存
  Future<void> setUpdateInterval(String value) async {
    final prefs = await _getPrefs();
    await prefs.setString(SettingsKeys.updateInterval, value);
    state = AsyncValue.data(prefs);
    // バックグラウンドタスクの間隔も即時反映
    await updateBackgroundTaskInterval(value);
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, SharedPreferences>(
        SettingsController.new);

/// 配達完了通知トグルの状態
/// prefs未解決時はデフォルト値（true）を返し、解決後に実際の値へ更新される。
final notifyDeliveryProvider = Provider<bool>((ref) {
  final prefs = ref.watch(settingsControllerProvider).valueOrNull;
  return prefs?.getBool(SettingsKeys.notifyDelivery) ?? true;
});

/// ステータス変更通知トグルの状態
final notifyStatusChangeProvider = Provider<bool>((ref) {
  final prefs = ref.watch(settingsControllerProvider).valueOrNull;
  return prefs?.getBool(SettingsKeys.notifyStatusChange) ?? false;
});

/// 更新間隔
final updateIntervalProvider = Provider<String>((ref) {
  final prefs = ref.watch(settingsControllerProvider).valueOrNull;
  return prefs?.getString(SettingsKeys.updateInterval) ?? '30分';
});

/// 配達完了通知トグルを更新する関数
final setNotifyDeliveryProvider = Provider<Future<void> Function(bool)>((ref) {
  final controller = ref.read(settingsControllerProvider.notifier);
  return controller.setNotifyDelivery;
});

/// ステータス変更通知トグルを更新する関数
final setNotifyStatusChangeProvider =
    Provider<Future<void> Function(bool)>((ref) {
  final controller = ref.read(settingsControllerProvider.notifier);
  return controller.setNotifyStatusChange;
});

/// 更新間隔を更新する関数
final setUpdateIntervalProvider =
    Provider<Future<void> Function(String)>((ref) {
  final controller = ref.read(settingsControllerProvider.notifier);
  return controller.setUpdateInterval;
});
