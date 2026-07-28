import 'package:trackflow/data/scraping/carrier_tracker.dart';
import 'package:trackflow/data/local/database.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/entities/tracking_event.dart' as domain;
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/domain/repositories/tracking_repository.dart';

/// TrackingRepositoryの実装
class TrackingRepositoryImpl implements TrackingRepository {
  final AppDatabase _database;

  TrackingRepositoryImpl(this._database);

  @override
  Future<TrackingInfo> fetchTracking({
    required String trackingNumber,
    required String carrier,
  }) async {
    final carrierEnum = Carrier.fromString(carrier);
    final tracker = TrackerFactory.create(carrierEnum);

    try {
      final info = await tracker.fetch(trackingNumber);

      // キャッシュに保存
      final historyId = await _database.saveHistory(
        trackingNumber,
        carrier,
        itemType: info.itemType,
        currentStatus: info.currentStatus,
        estimatedDelivery: info.estimatedDelivery,
      );

      await _database.saveEvents(
        historyId,
        info.events
            .map((e) => (
                  rawDate: e.rawDate,
                  status: e.status,
                  location: e.location,
                ))
            .toList(),
      );

      return info;
    } on TrackerException {
      // キャッシュから取得を試みる
      final cached =
          await _database.getLatestHistory(trackingNumber, carrier);
      if (cached != null) {
        final eventsData =
            await _database.getEventsForHistory(cached.id);
        return TrackingInfo(
          trackingNumber: trackingNumber,
          carrier: carrierEnum,
          itemType: cached.itemType,
          currentStatus: cached.currentStatus,
          estimatedDelivery: cached.estimatedDelivery,
          events: eventsData
              .map((e) => domain.TrackingEvent(
                    rawDate: e.rawDate,
                    date: null,
                    status: e.status,
                    location: e.location,
                  ))
              .toList(),
          lastUpdated: cached.fetchedAt,
        );
      }
      rethrow;
    }
  }

  @override
  bool isValidTrackingNumber(String number) {
    if (number.isEmpty) return false;
    final cleaned = number.replaceAll('-', '');
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) return false;
    return cleaned.length >= 10 && cleaned.length <= 14;
  }

  /// Carrierの文字列から自動判別を試みる
  static Carrier? detectCarrier(String trackingNumber) {
    final cleaned = trackingNumber.replaceAll('-', '');

    if (cleaned.length == 11 || cleaned.length == 13) {
      return Carrier.japanPost;
    }
    if (cleaned.length == 12) {
      return Carrier.yamato;
    }
    return null;
  }
}
