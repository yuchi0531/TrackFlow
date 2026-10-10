/// SharedPreferences の設定キー定数。
///
/// フォアグラウンド（`settings_provider.dart`）とバックグラウンドIsolate
/// （`background_provider.dart` の callbackDispatcher）の双方から参照される。
/// 両者が同じキーを読めないと設定が反映されないため、定義はこの1箇所に集約する。
/// （循環参照を避けるため、UI側 Provider からは独立した定数ファイルに置く）
class SettingsKeys {
  /// 配達完了通知トグル
  static const notifyDelivery = 'notify_delivery';

  /// ステータス変更通知トグル
  static const notifyStatusChange = 'notify_status_change';

  /// 配達予定日当日通知トグル
  static const deliveryDayNotify = 'delivery_day_notify';

  /// 自動更新間隔
  static const updateInterval = 'update_interval';

  SettingsKeys._();
}
