import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:trackflow/data/local/database.dart';
import 'package:trackflow/data/scraping/carrier_tracker.dart';
import 'package:trackflow/domain/entities/carrier.dart';

const _backgroundTaskName = 'trackflow_background_fetch';

FlutterLocalNotificationsPlugin? _notifications;

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
      final db = AppDatabase.inMemory();
      final saved = await db.getAllActive();

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

          if (info.currentStatus.contains('配達完了') ||
              info.currentStatus.contains('お届け済み')) {
            final prevStatus = prevHistory?.currentStatus ?? '';
            if (prevStatus != info.currentStatus) {
              await _showDeliveryNotification(
                item.trackingNumber,
                item.carrier,
              );
            }
          } else if (prevHistory != null &&
              prevHistory.currentStatus != info.currentStatus) {
            await _showStatusChangeNotification(
              item.trackingNumber,
              info.currentStatus,
              item.carrier,
            );
          }
        } catch (_) {}
      }
    } catch (_) {
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
      number.hashCode,
      '配達完了',
      '$carrier $number が配達完了しました',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  } catch (_) {}
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
      number.hashCode,
      '配送状況が更新されました',
      '$carrier $number: $status',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  } catch (_) {}
}

final backgroundProvider = Provider<void>((ref) {});

Future<void> initBackgroundService() async {
  try {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      'trackflow_periodic',
      _backgroundTaskName,
      frequency: const Duration(minutes: 30),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  } catch (_) {
    // バックグラウンドサービスの初期化に失敗してもアプリは継続
  }
}
