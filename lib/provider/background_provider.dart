import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:trackflow/data/local/database.dart';
import 'package:trackflow/data/scraping/carrier_tracker.dart';
import 'package:trackflow/domain/entities/carrier.dart';

const _backgroundTaskName = 'trackflow_background_fetch';
const _periodicTaskName = 'trackflow_periodic';

/// 設定キー（callbackDispatcherで直接SharedPreferencesを読むため定数化）
const _keyNotifyDelivery = 'notify_delivery';
const _keyNotifyStatusChange = 'notify_status_change';

FlutterLocalNotificationsPlugin? _notifications;

/// 通知用のユニークIDを生成
/// シンプルなインクリメント方式。同じIsolateライフタイム内で一意。
/// Dartのintは任意精度だが、AndroidのNotificationManagerは32ビットint期待のため
/// 値を小さく保つ（1セッションで数十件程度が上限）。
int _notificationId = 0;
int _nextNotificationId() => ++_notificationId;

Future<FlutterLocalNotificationsPlugin> _getNotifications() async {
  if (_notifications != null) return _notifications!;
  _notifications = FlutterLocalNotificationsPlugin();
  const androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  await _notifications!.initialize(
    const InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    ),
  );
  return _notifications!;
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // ユーザーの追跡データを読み取る（ファイルベースDB）
      final db = await AppDatabase.create();
      final saved = await db.getAllActive();

      // 通知設定をSharedPreferencesから読み取る
      final prefs = await SharedPreferences.getInstance();
      final notifyDelivery = prefs.getBool(_keyNotifyDelivery) ?? true;
      final notifyStatusChange = prefs.getBool(_keyNotifyStatusChange) ?? false;

      for (final item in saved) {
        try {
          final tracker = TrackerFactory.create(
              Carrier.fromString(item.carrier));
          final info = await tracker.fetch(item.trackingNumber);

          final prevHistory =
              await db.getLatestHistory(item.trackingNumber, item.carrier);

          final historyId = await db.saveHistory(
            item.trackingNumber,
            item.carrier,
            itemType: info.itemType,
            currentStatus: info.currentStatus,
            estimatedDelivery: info.estimatedDelivery,
          );

          await db.saveEvents(
            historyId,
            info.events
                .map((e) => (
                      rawDate: e.rawDate,
                      status: e.status,
                      location: e.location,
                    ))
                .toList(),
          );

          final isDelivered = info.currentStatus.contains('配達完了') ||
              info.currentStatus.contains('お届け済み');

          if (isDelivered && notifyDelivery) {
            final prevStatus = prevHistory?.currentStatus ?? '';
            if (prevStatus != info.currentStatus) {
              await _showDeliveryNotification(
                item.trackingNumber,
                item.carrier,
              );
            }
          } else if (!isDelivered && notifyStatusChange) {
            if (prevHistory != null &&
                prevHistory.currentStatus != info.currentStatus) {
              await _showStatusChangeNotification(
                item.trackingNumber,
                info.currentStatus,
                item.carrier,
              );
            }
          }
        } catch (e) {
          debugPrint(
              'Background fetch failed for ${item.trackingNumber}: $e');
        }
      }
    } catch (e) {
      debugPrint('Background task failed: $e');
      return false;
    }
    return true;
  });
}

Future<void> _showDeliveryNotification(
    String number, String carrier) async {
  try {
    final notifications = await _getNotifications();
    final androidDetails = const AndroidNotificationDetails(
      'delivery_channel',
      '配達完了',
      channelDescription: '荷物の配達が完了したことをお知らせします',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    await notifications.show(
      _nextNotificationId(),
      '配達完了',
      '$carrier $number が配達完了しました',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  } catch (e) {
    debugPrint('Delivery notification failed: $e');
  }
}

Future<void> _showStatusChangeNotification(
    String number, String status, String carrier) async {
  try {
    final notifications = await _getNotifications();
    final androidDetails = const AndroidNotificationDetails(
      'status_channel',
      'ステータス変更',
      channelDescription: '荷物の配送状況が変更されたことをお知らせします',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    await notifications.show(
      _nextNotificationId(),
      '配送状況が更新されました',
      '$carrier $number: $status',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  } catch (e) {
    debugPrint('Status change notification failed: $e');
  }
}

final backgroundProvider = Provider<void>((ref) {});

/// 更新間隔の文字列をDurationに変換
Duration _intervalToDuration(String interval) {
  switch (interval) {
    case '15分':
      return const Duration(minutes: 15);
    case '30分':
      return const Duration(minutes: 30);
    case '1時間':
      return const Duration(hours: 1);
    case '3時間':
      return const Duration(hours: 3);
    default:
      return const Duration(minutes: 30);
  }
}

/// バックグラウンドサービスを初期化する
Future<void> initBackgroundService() async {
  try {
    await Workmanager().initialize(callbackDispatcher);

    // 保存された更新間隔を読み取る
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getString('update_interval') ?? '30分';
    final frequency = _intervalToDuration(interval);

    await Workmanager().registerPeriodicTask(
      _periodicTaskName,
      _backgroundTaskName,
      frequency: frequency,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
    debugPrint('Background service initialized with interval: $interval');
  } catch (e) {
    debugPrint('Background service initialization failed: $e');
  }
}

/// 定期タスクをキャンセルして再登録する（更新間隔変更時に呼ぶ）
Future<void> updateBackgroundTaskInterval(String interval) async {
  try {
    await Workmanager().cancelByUniqueName(_periodicTaskName);
    final frequency = _intervalToDuration(interval);
    await Workmanager().registerPeriodicTask(
      _periodicTaskName,
      _backgroundTaskName,
      frequency: frequency,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
    debugPrint('Background task updated with interval: $interval');
  } catch (e) {
    debugPrint('Failed to update background task interval: $e');
  }
}
