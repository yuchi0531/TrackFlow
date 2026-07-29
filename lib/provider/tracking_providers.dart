import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/entities/tracking_event.dart' as domain;
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'database_provider.dart';
import 'tracking_repository_provider.dart';

final trackingListProvider = FutureProvider<List<TrackingInfo>>((ref) async {
  try {
    final db = await ref.watch(databaseProvider.future);
    final saved = await db.getAllActive();

    if (saved.isEmpty) return [];

    // バッチ取得: 1回のクエリで全履歴を取得
    final histories = await db.getAllLatestHistories();
    final historyIds = histories.values.map((h) => h.id).toList();
    final eventsByHistory =
        await db.getEventsForHistories(historyIds);

    final results = <TrackingInfo>[];
    for (final item in saved) {
      final key = '${item.trackingNumber}_${item.carrier}';
      final history = histories[key];
      if (history != null) {
        final carrierEnum = Carrier.fromString(item.carrier);
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
      }
    }
    return results;
  } catch (e) {
    debugPrint('Failed to load tracking list: $e');
    return [];
  }
});

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

    await db.insertTracking(trackingNumber, carrier, nickname: nickname);

    try {
      final repo = await ref.read(trackingRepositoryProvider.future);
      await repo.fetchTracking(
        trackingNumber: trackingNumber,
        carrier: carrier,
      );
    } catch (e) {
      debugPrint('Initial fetch failed for $trackingNumber: $e');
    }
  };
});

/// 追跡番号を削除するプロバイダー
final deleteTrackingProvider = Provider<Future<void> Function({
  required String trackingNumber,
  required String carrier,
})>((ref) {
  final dbFuture = ref.watch(databaseProvider.future);

  return ({
    required String trackingNumber,
    required String carrier,
  }) async {
    final db = await dbFuture;
    final saved = await db.findByTrackingNumber(trackingNumber, carrier);
    if (saved != null) {
      await db.deleteTracking(saved.id);
    }
  };
});
