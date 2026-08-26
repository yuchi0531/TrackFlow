import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:trackflow/data/local/database.dart';
import 'package:trackflow/data/scraping/carrier_tracker.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'widget_snapshot_provider.dart';

const _backgroundTaskName = 'trackflow_background_fetch';
const _periodicTaskName = 'trackflow_periodic';

/// 設定キー（callbackDispatcherで直接SharedPreferencesを読むため定数化）
const _keyNotifyDelivery = 'notify_delivery';
const _keyNotifyStatusChange = 'notify_status_change';
const _keyNotifyDeliveryDay = 'delivery_day_notify';

/// 配達予定日当日の通知済み記録キーのプレフィックス
/// `delivery_day_notified_<追跡番号>` = `YYYY/MM/DD`（同一日は再通知しない）
const _deliveryDayNotifiedPrefix = 'delivery_day_notified_';

FlutterLocalNotificationsPlugin? _notifications;

/// 通知用のユニークIDを生成
/// 追跡番号から決定的に安定生成する。
/// AndroidのNotificationManagerは32ビットint期待のため、ビットマスクして小さく保つ。
/// 同一の追跡番号には常に同じIDが割り当てられ、通知の上書き更新が可能。
///
/// Dart の `String.hashCode` はプロセスをまたぐ同一性が保証されないため、
/// workmanager の定期タスク（別プロセスで起動）でも同一結果が得られるよう
/// FNV-1a ハッシュを自前実装している。
@visibleForTesting
int notificationIdFor(String number) {
  // FNV-1a 32bitハッシュ（offset basis 0x811c9dc5, prime 0x01000193）
  var hash = 0x811c9dc5;
  for (final codeUnit in number.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  // 負値を避けるため上位ビットをマスク（0以上を保証）
  final masked = hash & 0x7FFFFFFF;
  // 0は無効IDのため1以上を保証
  return (masked % 2000000000) + 1;
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
      final notifyDeliveryDay = prefs.getBool(_keyNotifyDeliveryDay) ?? true;

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

          // 配達予定日当日の通知（設定ON・配達完了済み以外・1日1回のみ）
          if (notifyDeliveryDay &&
              !isDelivered &&
              isDeliveryToday(info.estimatedDelivery)) {
            final todayKey = _dateKeyString(DateTime.now());
            final notifiedKey =
                '$_deliveryDayNotifiedPrefix${item.trackingNumber}';
            if (prefs.getString(notifiedKey) != todayKey) {
              await _showDeliveryDayNotification(
                item.trackingNumber,
                item.carrier,
              );
              await prefs.setString(notifiedKey, todayKey);
            }
          }
        } catch (e) {
          debugPrint(
              'Background fetch failed for ${item.trackingNumber}: $e');
        }
      }

      // ウィジェット用スナップショットを更新（バックグラウンドIsolateでは
      // MethodChannel が使えないため SharedPreferences への保存のみ行う。
      // ネイティブ側の反映は次回フォアグラウンドでの更新時に実施される）
      await updateWidgetSnapshot(db: db, notifyNative: false);
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

/// 配達予定日当日の通知を表示する。
/// 既存の `status_channel` を再利用し、通知IDも `notificationIdFor(number)` で
/// 同一番号への通知上書きを維持する。
Future<void> _showDeliveryDayNotification(
    String number, String carrier) async {
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
      '本日お届け予定',
      '$carrier $number は本日のお届け予定です',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  } catch (e) {
    debugPrint('Delivery day notification failed: $e');
  }
}

final backgroundProvider = Provider<void>((ref) {});

/// ステータス文字列が配達完了を示すかどうかを判定する。
/// 各社の配達完了表現を網羅する。
/// 一覧画面の絞り込み・自動アーカイブからも使用するため公開関数とする。
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

/// 配達予定日文字列が「今日」の日付かどうかを判定する。
///
/// 各社の生テキスト形式に対応:
/// - `YYYY/MM/DD`（例: 佐川 `配達予定日 2026/08/16`、ヤマト `2026/08/16（土）`）
/// - `M/D` 年なし（例: ヤマト `8/16（金）09:00〜11:00`）
///
/// 年なしの場合は現在年を仮定し、未来日付なら年を1つ戻す
/// （既存のヤマト/佐川トラッカー `_parseDate` と同じ年跨ぎロジック）。
/// 日付を抽出できない場合は false。
@visibleForTesting
bool isDeliveryToday(String? estimatedDelivery) {
  if (estimatedDelivery == null || estimatedDelivery.isEmpty) return false;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // YYYY/MM/DD 形式を優先して抽出（年なし抽出が年付きの一部に掛からないように）
  final fullMatch =
      RegExp(r'(\d{4})/(\d{1,2})/(\d{1,2})').firstMatch(estimatedDelivery);
  if (fullMatch != null) {
    final month = int.parse(fullMatch.group(2)!);
    final day = int.parse(fullMatch.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return false;
    return DateTime(int.parse(fullMatch.group(1)!), month, day) == today;
  }

  // 年なし M/D 形式
  final shortMatch =
      RegExp(r'(\d{1,2})/(\d{1,2})').firstMatch(estimatedDelivery);
  if (shortMatch != null) {
    final month = int.parse(shortMatch.group(1)!);
    final day = int.parse(shortMatch.group(2)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return false;
    var date = DateTime(now.year, month, day);
    // 未来日付なら年を1つ戻す（年跨ぎ対応）
    if (date.isAfter(now)) date = DateTime(now.year - 1, month, day);
    return date == today;
  }

  return false;
}

/// 日付を `YYYY/MM/DD` 形式の文字列にする（配達予定日当日の通知済み判定キー用）
String _dateKeyString(DateTime date) {
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  return '${date.year}/$mm/$dd';
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
