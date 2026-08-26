import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackflow/data/local/database.dart';
import 'package:trackflow/domain/entities/carrier.dart';

/// ウィジェット用スナップショットのSharedPreferencesキー。
///
/// shared_preferences プラグインはキーに `flutter.` プレフィックスを付与するため、
/// ネイティブ側（AppWidgetProvider）では `flutter.trackflow_widget_snapshot` として
/// `FlutterSharedPreferences` ファイルから読む。
const widgetSnapshotKey = 'trackflow_widget_snapshot';

/// ウィジェットに表示する最大件数（レイアウトの固定行数と一致させる）
const kWidgetMaxItems = 4;

/// ネイティブ側 `WidgetSnapshotChannel`（Kotlin）との通信チャネル。
class WidgetSnapshotChannel {
  const WidgetSnapshotChannel();

  static const _channel =
      MethodChannel('com.trackflow.trackflow/widget_snapshot');

  /// ネイティブ側の `TrackingWidgetProvider` に全ウィジェットの再描画を依頼する。
  ///
  /// MethodChannel は UI Isolate でしか利用できない。バックグラウンド Isolate や
  /// テスト環境では MissingPluginException 等になるため、ここで catch して
  /// クラッシュさせない（呼び出し元に伝播させない）。
  Future<void> updateWidget() async {
    try {
      await _channel.invokeMethod<void>('updateWidget');
      debugPrint('Widget snapshot channel: update requested');
    } catch (e) {
      debugPrint('Widget update via MethodChannel failed: $e');
    }
  }
}

/// 追跡一覧のスナップショットをSharedPreferencesへ保存する。
///
/// フォーマット:
/// ```json
/// {
///   "total": 6,
///   "items": [
///     {"trackingNumber": "...", "carrier": "yamato",
///      "carrierDisplay": "ヤマト運輸", "currentStatus": "...",
///      "nickname": null, "lastUpdated": "2026-08-13T05:00:00.000"}
///   ]
/// }
/// ```
/// `items` は最大 [kWidgetMaxItems] 件（最新登録順）+ `total` に総数を保持する。
///
/// - [db] 指定時はその接続を使用する（寿命管理は呼び出し元）。null なら内部で
///   `AppDatabase.create()` し、処理完了後にクローズする。
/// - [notifyNative] が true なら保存後に MethodChannel 経由でネイティブウィジェットの
///   再描画も依頼する。バックグラウンド Isolate では MethodChannel が使えないため
///   false を渡し、保存のみ行う（反映は次回フォアグラウンド更新時）。
///
/// 全ての例外は握りつぶして debugPrint のみ行う（テスト環境・プラグイン未初期化でも
/// クラッシュさせない）。
Future<void> updateWidgetSnapshot({
  AppDatabase? db,
  bool notifyNative = true,
}) async {
  AppDatabase? opened;
  try {
    final database = db ?? (opened = await AppDatabase.create());
    final saved = await database.getAllActive();
    final histories = await database.getAllLatestHistories();

    final items = <Map<String, dynamic>>[];
    for (final s in saved.take(kWidgetMaxItems)) {
      final history = histories['${s.trackingNumber}_${s.carrier}'];
      items.add({
        'trackingNumber': s.trackingNumber,
        'carrier': s.carrier,
        'carrierDisplay': Carrier.fromString(s.carrier).displayName,
        'currentStatus': history?.currentStatus ?? '情報を取得できませんでした',
        'nickname': s.nickname,
        'lastUpdated': history?.fetchedAt.toIso8601String(),
      });
    }

    final snapshot = jsonEncode({'total': saved.length, 'items': items});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(widgetSnapshotKey, snapshot);
    debugPrint('Widget snapshot saved (total=${saved.length})');

    if (notifyNative) {
      await WidgetSnapshotChannel().updateWidget();
    }
  } catch (e) {
    debugPrint('updateWidgetSnapshot failed: $e');
  } finally {
    if (opened != null) {
      try {
        await opened.close();
      } catch (e) {
        debugPrint('Failed to close snapshot database: $e');
      }
    }
  }
}