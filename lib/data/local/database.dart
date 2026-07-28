import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// ユーザーが保存した追跡番号
class SavedTrackings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackingNumber => text().named('tracking_number')();
  TextColumn get carrier => text()();
  TextColumn get nickname => text().nullable()();
  BoolColumn get isActive => boolean().named('is_active').withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().named('created_at').withDefault(currentDateAndTime)();
}

/// 追跡履歴のキャッシュ
class TrackingHistories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackingNumber => text().named('tracking_number')();
  TextColumn get carrier => text()();
  TextColumn get itemType => text().named('item_type').nullable()();
  TextColumn get currentStatus => text().named('current_status')();
  TextColumn get estimatedDelivery => text().named('estimated_delivery').nullable()();
  DateTimeColumn get fetchedAt => dateTime().named('fetched_at').withDefault(currentDateAndTime)();
}

/// 追跡イベント
class TrackingEventEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get historyId => integer().named('history_id').references(TrackingHistories, #id)();
  TextColumn get rawDate => text().named('raw_date')();
  TextColumn get status => text()();
  TextColumn get location => text().nullable()();
}

@DriftDatabase(tables: [SavedTrackings, TrackingHistories, TrackingEventEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.e) ;

  /// 非同期ファクトリ - asyncパス解決を行う
  static Future<AppDatabase> create() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File('${dbFolder.path}/trackflow.sqlite');
    return AppDatabase._(NativeDatabase(file));
  }

  /// テスト/フォールバック用 - インメモリDB
  AppDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  Future<List<SavedTracking>> getAllActive() {
    return (select(savedTrackings)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<SavedTracking?> findByTrackingNumber(String number, String carrier) {
    return (select(savedTrackings)
          ..where((t) =>
              t.trackingNumber.equals(number) & t.carrier.equals(carrier)))
        .getSingleOrNull();
  }

  Future<int> insertTracking(String trackingNumber, String carrier,
      {String? nickname}) {
    return into(savedTrackings).insert(
      SavedTrackingsCompanion(
        trackingNumber: Value(trackingNumber),
        carrier: Value(carrier),
        nickname: Value(nickname),
      ),
    );
  }

  Future<int> deleteTracking(int id) {
    return (update(savedTrackings)..where((t) => t.id.equals(id))).write(
      SavedTrackingsCompanion(isActive: const Value(false)),
    );
  }

  Future<TrackingHistory?> getLatestHistory(
      String trackingNumber, String carrier) {
    return (select(trackingHistories)
          ..where((t) =>
              t.trackingNumber.equals(trackingNumber) &
              t.carrier.equals(carrier))
          ..orderBy([(t) => OrderingTerm.desc(t.fetchedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int> saveHistory(String trackingNumber, String carrier,
      {String? itemType,
      required String currentStatus,
      String? estimatedDelivery}) {
    return into(trackingHistories).insert(
      TrackingHistoriesCompanion(
        trackingNumber: Value(trackingNumber),
        carrier: Value(carrier),
        itemType: Value(itemType),
        currentStatus: Value(currentStatus),
        estimatedDelivery: Value(estimatedDelivery),
      ),
    );
  }

  Future<List<TrackingEventEntry>> getEventsForHistory(int historyId) {
    return (select(trackingEventEntries)
          ..where((t) => t.historyId.equals(historyId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  Future<void> saveEvents(
      int historyId,
      List<({String rawDate, String status, String? location})>
          events) async {
    await batch((batch) {
      batch.insertAll(
        trackingEventEntries,
        events.map((e) => TrackingEventEntriesCompanion(
              historyId: Value(historyId),
              rawDate: Value(e.rawDate),
              status: Value(e.status),
              location: Value(e.location),
            )),
      );
    });
  }
}
