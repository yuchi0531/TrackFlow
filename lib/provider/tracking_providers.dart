import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/entities/tracking_event.dart' as domain;
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'database_provider.dart';
import 'tracking_repository_provider.dart';

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
    return results;
  }

  /// 追跡を削除する。DB削除前に state から即時除去して、
  /// 削除したアイテムが一瞬戻るフリッカーを防ぐ。
  Future<void> delete({
    required String trackingNumber,
    required String carrier,
  }) async {
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
  }
}

final trackingDetailProvider =
    FutureProvider.family<TrackingInfo, ({String number, String carrier})>(
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
