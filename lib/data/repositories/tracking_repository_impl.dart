import 'dart:async';
import 'package:trackflow/data/scraping/carrier_tracker.dart';
import 'package:trackflow/data/local/database.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/entities/tracking_event.dart' as domain;
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/domain/repositories/tracking_repository.dart';
import 'package:trackflow/domain/tracking_number.dart';

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
  static bool isValidTrackingNumberStatic(String number) =>
      TrackingNumberValidator.isValid(number);

  /// 追跡番号の桁数からキャリアを自動判別する。
  ///
  /// domain 層のユーティリティを参照する薄いラッパー。
  static Carrier? detectCarrier(String trackingNumber) =>
      TrackingNumberValidator.detectCarrier(trackingNumber);
}
