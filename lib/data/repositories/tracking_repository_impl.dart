import 'dart:async';
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
      return _getCachedOrThrow(trackingNumber, carrier, carrierEnum);
    } on TimeoutException {
      return _getCachedOrThrow(trackingNumber, carrier, carrierEnum);
    } on Exception {
      final trackerExc = TrackerException(
        type: TrackerErrorType.networkFailure,
        message: '予期しないエラーが発生しました',
      );
      return _getCached(trackingNumber, carrier, carrierEnum, () => throw trackerExc);
    }
  }

  Future<TrackingInfo> _getCached(
      String trackingNumber, String carrier, Carrier carrierEnum,
      void Function() onMiss) async {
    final cached = await _database.getLatestHistory(trackingNumber, carrier);
    if (cached != null) {
      final eventsData = await _database.getEventsForHistory(cached.id);
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
    onMiss();
    throw UnsupportedError('onMiss must throw'); // この行には到達しない（onMissが必ずthrowする）
  }

  Future<TrackingInfo> _getCachedOrThrow(
      String trackingNumber, String carrier, Carrier carrierEnum) {
    return _getCached(trackingNumber, carrier, carrierEnum, () {
      throw TrackerException(
        type: TrackerErrorType.notFound,
        message: '追跡情報が取得できません',
      );
    });
  }

  @override
  bool isValidTrackingNumber(String number) => isValidTrackingNumberStatic(number);

  /// 追跡番号の形式を検証する（インスタンス不要の静的ヘルパー）
  static bool isValidTrackingNumberStatic(String number) {
    if (number.isEmpty) return false;
    final cleaned = number.replaceAll('-', '');
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) return false;
    return cleaned.length >= 10 && cleaned.length <= 14;
  }

  /// 追跡番号の桁数からキャリアを自動判別する。
  ///
  /// - 11桁または13桁: 日本郵便
  /// - 12桁: ヤマト運輸（佐川急便も12桁のため判別不可、手動選択が必要）
  ///
  /// 佐川急便の追跡番号はヤマト運輸と同じ12桁のケースが多く、
  /// 桁数のみでは両者を確実に区別できないため、12桁の場合はヤマト運輸を優先する。
  /// それ以外の桁数（10桁や14桁など）の場合は null を返す。
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
