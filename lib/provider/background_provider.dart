import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
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
/// 追跡番号のハッシュから安定生成する。
/// AndroidのNotificationManagerは32ビットint期待のため、ビットマスクして小さく保つ。
/// 同一の追跡番号には常に同じIDが割り当てられ、通知の上書き更新が可能。
@visibleForTesting
int notificationIdFor(String number) {
  // 追跡番号から安定した32ビットintを生成
  final hash = number.hashCode & 0x7FFFFFFF;
  // 0は無効IDのため1以上を保証
  return (hash % 2000000000) + 1;
}

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

/// Android 13+ で通知を表示するために必要な POST_NOTIFICATIONS 権限をリクエストする。
///
/// - Android 13 (API 33) 以降: システムダイアログを表示して権限を要求
/// - それ以前: 自動で付与されるため true
/// - ユーザーが永久拒否している場合は false を返す（設定画面から手動許可が必要）
///
/// 戻り値: 権限が付与されたかどうか（false = ユーザーが拒否 or 未対応）
Future<bool> requestNotificationPermissions() async {
  try {
    // 既に許可済みなら即 true
    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    // 通知チャンネルを先に作成（権限と独立して作成可能）
    await initNotificationChannels();

    // 永久拒否（don't ask again）の場合はダイアログが出ない
    if (status.isPermanentlyDenied) return false;

    // リクエスト
    final result = await Permission.notification.request();
    return result.isGranted;
  } catch (e) {
    debugPrint('Notification permission request failed: $e');
    return false;
  }
}

/// システムの通知設定画面を開く。
/// ユーザーが権限を拒否（永久拒否含む）した場合に、手動で許可してもらうために使用する。
Future<bool> openNotificationSettings() async {
  try {
    return await openAppSettings();
  } catch (e) {
    debugPrint('Open notification settings failed: $e');
    return false;
  }
}

/// 通知権限が付与されているかどうかを確認する。
/// 権限リクエストの状態をUIに反映するために使用する。
Future<bool> areNotificationsEnabled() async {
  try {
    final status = await Permission.notification.status;
    return status.isGranted;
  } catch (e) {
    debugPrint('Notification permission check failed: $e');
    return true;
  }
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

      // 通知チャンネルを確実に作成（バックグラウンドIsolateでも必要）
      await initNotificationChannels();

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

          final isDelivered = isDeliveredStatus(info.currentStatus);

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

/// 通知チャンネルを事前作成する。
/// 権限リクエストと独立して作成可能。権限が付与されれば通知を表示できる。
Future<void> initNotificationChannels() async {
  try {
    final notifications = await _getNotifications();
    final androidImpl = notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        'delivery_channel',
        '配達完了',
        description: '荷物の配達が完了したことをお知らせします',
        importance: Importance.high,
      ),
    );
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        'status_channel',
        'ステータス変更',
        description: '荷物の配送状況が変更されたことをお知らせします',
        importance: Importance.defaultImportance,
      ),
    );
  } catch (e) {
    debugPrint('Notification channel creation failed: $e');
  }
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
      notificationIdFor(number),
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
      notificationIdFor(number),
      '配送状況が更新されました',
      '$carrier $number: $status',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  } catch (e) {
    debugPrint('Status change notification failed: $e');
  }
}

final backgroundProvider = Provider<void>((ref) {});

/// ステータス文字列が配達完了を示すかどうかを判定する。
/// 各社の配達完了表現を網羅する。
@visibleForTesting
bool isDeliveredStatus(String status) {
  final deliveredKeywords = [
    '配達完了', // ヤマト・佐川
    'お届け済み', // 日本郵便
    '投函完了', // 日本郵便（ポスト投函）
    '配達済み', // 佐川
    'お届け完了', // 佐川
  ];
  return deliveredKeywords.any(status.contains);
}

/// 更新間隔の文字列をDurationに変換
@visibleForTesting
Duration intervalToDuration(String interval) {
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
    final frequency = intervalToDuration(interval);

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
    final frequency = intervalToDuration(interval);
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
