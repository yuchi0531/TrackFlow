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

  /// 全アクティブな追跡に対する最新の履歴を一括取得
  /// trackingNumber+carrierの組み合わせごとに最新の履歴を返す。
  /// auto-increment IDを使用（INSERT順が更新順と等価であることを前提）。
  Future<Map<String, TrackingHistory>> getAllLatestHistories() async {
    final maxIdRows = await (selectOnly(trackingHistories)
          ..addColumns([trackingHistories.id.max()])
          ..groupBy([trackingHistories.trackingNumber, trackingHistories.carrier]))
        .map((row) => row.read(trackingHistories.id.max()))
        .get();

    final maxIds = <int>[];
    for (final id in maxIdRows) {
      if (id != null) maxIds.add(id);
    }
    if (maxIds.isEmpty) return {};

    final histories = await (select(trackingHistories)
          ..where((t) => t.id.isIn(maxIds)))
        .get();

    final result = <String, TrackingHistory>{};
    for (final h in histories) {
      final key = '${h.trackingNumber}_${h.carrier}';
      result[key] = h;
    }
    return result;
  }

  /// 複数の履歴IDに対するイベントを一括取得
  Future<Map<int, List<TrackingEventEntry>>> getEventsForHistories(
      List<int> historyIds) async {
    if (historyIds.isEmpty) return {};

    final events = await (select(trackingEventEntries)
          ..where((t) => t.historyId.isIn(historyIds))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();

    final result = <int, List<TrackingEventEntry>>{};
    for (final e in events) {
      result.putIfAbsent(e.historyId, () => []).add(e);
    }
    return result;
  }

  /// 追跡履歴を保存する。
  ///
  /// 最新の履歴とステータスが同じ場合は新規レコードを作成せず、
  /// 既存レコードの `fetchedAt` と付随情報を更新する。
  /// ステータスが変化した場合のみ新規レコードを挿入する。
  ///
  /// これにより `TrackingHistories` テーブルの肥大化を防ぎつつ、
  /// ステータス変更時は履歴として残るため通知判定（前回と比較）にも使える。
  Future<int> saveHistory(String trackingNumber, String carrier,
      {String? itemType,
      required String currentStatus,
      String? estimatedDelivery}) async {
    final latest = await getLatestHistory(trackingNumber, carrier);
    if (latest != null && latest.currentStatus == currentStatus) {
      // ステータスが変わっていない場合は既存レコードを更新
      await (update(trackingHistories)
            ..where((t) => t.id.equals(latest.id)))
          .write(
        TrackingHistoriesCompanion(
          itemType: Value(itemType),
          estimatedDelivery: Value(estimatedDelivery),
          fetchedAt: Value(DateTime.now()),
        ),
      );
      return latest.id;
    }

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

  /// 履歴にイベントを保存する。
  ///
  /// 同一の `historyId` に対する既存イベントを一旦削除してから
  /// 新しいイベントを挿入する。これにより、
  /// ステータスが変わらず `saveHistory` が既存レコードを更新した場合でも
  /// イベントが重複しない。
  Future<void> saveEvents(
      int historyId,
      List<({String rawDate, String status, String? location})>
          events) async {
    if (events.isEmpty) return;

    await batch((batch) {
      batch.deleteWhere(
        trackingEventEntries,
        (t) => t.historyId.equals(historyId),
      );
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
