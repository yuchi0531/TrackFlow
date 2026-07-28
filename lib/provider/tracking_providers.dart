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

    final results = <TrackingInfo>[];
    for (final item in saved) {
      try {
        final history = await db.getLatestHistory(
            item.trackingNumber, item.carrier);
        if (history != null) {
          final events = await db.getEventsForHistory(history.id);
          final carrierEnum = Carrier.fromString(item.carrier);

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
      } catch (_) {}
    }
    return results;
  } catch (_) {
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
    } catch (_) {}
  };
});
