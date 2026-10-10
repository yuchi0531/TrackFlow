import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/entities/tracking_event.dart' as domain;
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/domain/tracking_number.dart';
import 'database_provider.dart';
import 'tracking_repository_provider.dart';
import 'widget_snapshot_provider.dart';

final trackingListProvider = AsyncNotifierProvider<TrackingListNotifier,
    List<TrackingInfo>>(TrackingListNotifier.new);

/// 追跡一覧を管理するNotifier。
///
/// `build()` で一覧を取得し、削除時にはDB削除前に state から該当アイテムを
/// 同期的に除去することで、FutureProvider のような「更新中も古いdataを返す」
/// フリッカー（Dismissible の「まだツリー内に残っている」アサーション）を回避する。
class TrackingListNotifier extends AsyncNotifier<List<TrackingInfo>> {
  @override
  Future<List<TrackingInfo>> build() async {
    final db = await ref.watch(databaseProvider.future);
    final saved = await db.getAllActive();

    if (saved.isEmpty) return [];

    // バッチ取得: 1回のクエリで全履歴を取得
    final histories = await db.getAllLatestHistories();
    final historyIds = histories.values.map((h) => h.id).toList();
    final eventsByHistory = await db.getEventsForHistories(historyIds);

    final results = <TrackingInfo>[];
    for (final item in saved) {
      final key = '${item.trackingNumber}_${item.carrier}';
      final history = histories[key];
      final carrierEnum = Carrier.fromString(item.carrier);

      if (history != null) {
        final events = eventsByHistory[history.id] ?? [];

        results.add(TrackingInfo(
          trackingNumber: item.trackingNumber,
          carrier: carrierEnum,
          itemType: history.itemType,
          currentStatus: history.currentStatus,
          estimatedDelivery: history.estimatedDelivery,
          events: events
              .map((e) => domain.TrackingEvent(
                    rawDate: e.rawDate,
                    date: null,
                    status: e.status,
                    location: e.location,
                  ))
              .toList(),
          lastUpdated: history.fetchedAt,
        ));
      } else {
        // 初回fetchが失敗した場合など履歴が存在しない場合は、
        // 一覧から消えないようプレースホルダーとして表示する。
        // タップで詳細画面から再取得を試みられる。
        results.add(TrackingInfo(
          trackingNumber: item.trackingNumber,
          carrier: carrierEnum,
          itemType: null,
          currentStatus: '情報を取得できませんでした',
          events: const [],
        ));
      }
    }

    // ウィジェット用スナップショットを非同期で更新（fire-and-forget）
    // 一覧更新のたびにホーム画面ウィジェットへ最新ステータスを反映する。
    unawaited(updateWidgetSnapshot(db: db));
    return results;
  }

  /// 追跡を削除する。DB削除前に state から即時除去して、
  /// 削除したアイテムが一瞬戻るフリッカーを防ぐ。
  Future<void> delete({
    required String trackingNumber,
    required String carrier,
  }) async {
    // 一覧の表示値は正規化済みだが、防御的に正規化してから検索する
    // （レガシーのハイフン付き保存値でも検索にヒットする）
    trackingNumber = TrackingNumberValidator.normalize(trackingNumber);
    final current = state.value;
    if (current != null) {
      state = AsyncData(current
          .where((t) =>
              t.trackingNumber != trackingNumber || t.carrier.name != carrier)
          .toList());
    }

    final db = await ref.read(databaseProvider.future);
    final saved = await db.findByTrackingNumber(trackingNumber, carrier);
    if (saved != null) {
      await db.deleteTracking(saved.id);
    }

    // 削除後にウィジェット用スナップショットを非同期で更新（fire-and-forget）
    unawaited(updateWidgetSnapshot(db: db));
  }
}

/// 詳細画面の追跡情報を取得する。
///
/// `.autoDispose` により、詳細画面を閉じると状態が破棄される。これにより
/// 再度同じ追跡を開いた際に必ず最新を取り直す（前回値のキャッシュ固定を防ぐ）。
final trackingDetailProvider = FutureProvider.autoDispose
    .family<TrackingInfo, ({String number, String carrier})>(
  (ref, params) async {
    final repo = await ref.watch(trackingRepositoryProvider.future);
    return repo.fetchTracking(
      trackingNumber: params.number,
      carrier: params.carrier,
    );
  },
);

final addTrackingProvider = Provider<Future<void> Function({
  required String trackingNumber,
  required String carrier,
  String? nickname,
})>((ref) {
  return ({
    required String trackingNumber,
    required String carrier,
    String? nickname,
  }) async {
    // 追跡番号を正規化（ハイフン除去）してから重複チェック・fetch・保存を行う。
    // これによりハイフンの有無で別レコードになることを防ぎ、
    // 各社へのスクレイピング送信も数字のみになる。
    trackingNumber = TrackingNumberValidator.normalize(trackingNumber);

    final db = await ref.read(databaseProvider.future);
    final existing =
        await db.findByTrackingNumber(trackingNumber, carrier);
    if (existing != null) {
      throw Exception('この追跡番号は既に登録されています');
    }

    // 先に追跡情報を取得して成功した場合のみ登録する。
    // これにより、初期状態から履歴が表示され、
    // 取得失敗時に「登録されたが履歴が空」という中途半端な状態を防ぐ。
    final repo = await ref.read(trackingRepositoryProvider.future);
    await repo.fetchTracking(
      trackingNumber: trackingNumber,
      carrier: carrier,
    );

    await db.insertTracking(trackingNumber, carrier, nickname: nickname);
  };
});

/// 配送会社を自動判定して追跡を追加する。
///
/// 桁数から候補を絞り、各社へ順に問い合わせて最初に取得できた会社で登録する。
/// 取得できた会社（[Carrier]）を返す。どの会社でも取得できなかった場合は
/// 例外を投げず null を返す（候補が存在しない、または全社で見つからない場合）。
///
/// 登録済み判定は判定した会社に対して行う。番号そのものが既に別の会社で
/// 登録済みでも、自動判定では気づけない可能性がある点に注意。
final addTrackingAutoProvider = Provider<
    Future<Carrier?> Function({
      required String trackingNumber,
      String? nickname,
    })>((ref) {
  return ({
    required String trackingNumber,
    String? nickname,
  }) async {
    trackingNumber = TrackingNumberValidator.normalize(trackingNumber);

    final db = await ref.read(databaseProvider.future);
    // 自動判定では会社が未確定のため、どの会社で登録済みでも重複とみなす
    // （判定結果と別会社で既登録のケースを取りこぼさない）。
    for (final carrier in Carrier.values) {
      final existing =
          await db.findByTrackingNumber(trackingNumber, carrier.name);
      if (existing != null) {
        throw Exception('この追跡番号は既に登録されています');
      }
    }

    final repo = await ref.read(trackingRepositoryProvider.future);
    final detected = await repo.detectCarrierAndFetch(trackingNumber);
    if (detected == null) return null;

    await db.insertTracking(
      trackingNumber,
      detected.carrier.name,
      nickname: nickname,
    );
    return detected.carrier;
  };
});
