import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trackflow/domain/tracking_number.dart';

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

  /// 追跡番号（ハイフン有無どちらでも）とキャリアで検索する。
  ///
  /// 新規レコードは [insertTracking] で正規化（ハイフン除去）済みの数字のみで保存されるが、
  /// 正規化導入前のレガシーデータにはハイフン付きで保存されたものもある。
  /// まず正規化済みと生の両方でSQL検索し、見つからない場合は保存値を正規化して
  /// 比較することで、ハイフンの有無にかかわらず同一の追跡として検索できる。
  Future<SavedTracking?> findByTrackingNumber(String number, String carrier) async {
    final normalized = TrackingNumberValidator.normalize(number);
    final direct = await (select(savedTrackings)
          ..where((t) =>
              (t.trackingNumber.equals(normalized) |
                  t.trackingNumber.equals(number)) &
              t.carrier.equals(carrier)))
        .getSingleOrNull();
    if (direct != null) return direct;

    // レガシーフォールバック: ハイフン付きで保存されたレコードは
    // 正規化済み番号のSQL検索にヒットしないため、保存値を正規化して比較する。
    final candidates = await (select(savedTrackings)
          ..where((t) => t.carrier.equals(carrier)))
        .get();
    for (final candidate in candidates) {
      if (TrackingNumberValidator.normalize(candidate.trackingNumber) ==
          normalized) {
        return candidate;
      }
    }
    return null;
  }

  Future<int> insertTracking(String trackingNumber, String carrier,
      {String? nickname}) {
    return into(savedTrackings).insert(
      SavedTrackingsCompanion(
        trackingNumber:
            Value(TrackingNumberValidator.normalize(trackingNumber)),
        carrier: Value(carrier),
        nickname: Value(nickname),
      ),
    );
  }

  /// 追跡を物理削除する。
  ///
  /// ソフトデリート（isActive=false）だと行が蓄積し続け、
  /// `findByTrackingNumber` がフィルタしないため再登録できなくなる。
  /// ハードデリートにより行が残らず、削除後の再登録が可能になる。
  ///
  /// 併せて、その追跡に紐づく `TrackingHistories` と `TrackingEventEntries` も
  /// 削除する。履歴を残すと以下の不具合が生じるため:
  /// - 削除→再登録時に古いキャッシュが最新履歴として復活し、再取得前に
  ///   古いステータスが一覧に表示される
  /// - 孤児行が SQLite ファイル内に無期限に蓄積する
  ///
  /// レガシーデータ（ハイフン付き保存）も取りこぼさないよう、保存値を正規化して比較する。
  Future<int> deleteTracking(int id) async {
    final saved = await (select(savedTrackings)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (saved == null) return 0;

    final normalized = TrackingNumberValidator.normalize(saved.trackingNumber);
    final histories = await (select(trackingHistories)
          ..where((t) => t.carrier.equals(saved.carrier)))
        .get();
    final historyIds = <int>[];
    for (final h in histories) {
      if (TrackingNumberValidator.normalize(h.trackingNumber) == normalized) {
        historyIds.add(h.id);
      }
    }

    return transaction(() async {
      if (historyIds.isNotEmpty) {
        await (delete(trackingEventEntries)
              ..where((t) => t.historyId.isIn(historyIds)))
            .go();
        await (delete(trackingHistories)
              ..where((t) => t.id.isIn(historyIds)))
            .go();
      }
      return (delete(savedTrackings)..where((t) => t.id.equals(id))).go();
    });
  }

  /// 追跡番号（ハイフン有無どちらでも）とキャリアで最新の履歴を取得する。
  ///
  /// 履歴テーブルにも正規化導入前のレガシーデータ（ハイフン付きキー）が
  /// 残っているため、まず正規化済みと生の両方でSQL検索し、見つからない場合は
  /// 保存値を正規化して比較する。
  Future<TrackingHistory?> getLatestHistory(
      String trackingNumber, String carrier) async {
    final normalized = TrackingNumberValidator.normalize(trackingNumber);
    // fetchedAt が同一秒の場合に備え、auto-increment の id を副キーに使う
    // （INSERT順 = 更新順のため、id 降順が真の最新）。
    final direct = await (select(trackingHistories)
          ..where((t) =>
              (t.trackingNumber.equals(normalized) |
                  t.trackingNumber.equals(trackingNumber)) &
              t.carrier.equals(carrier))
          ..orderBy([
            (t) => OrderingTerm.desc(t.fetchedAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (direct != null) return direct;

    // レガシーフォールバック: ハイフン付きで保存された履歴は
    // 正規化済み番号のSQL検索にヒットしないため、保存値を正規化して比較する。
    // 最新のもの（fetchedAt降順）から順に比較する。
    final candidates = await (select(trackingHistories)
          ..where((t) => t.carrier.equals(carrier))
          ..orderBy([(t) => OrderingTerm.desc(t.fetchedAt)]))
        .get();
    for (final candidate in candidates) {
      if (TrackingNumberValidator.normalize(candidate.trackingNumber) ==
          normalized) {
        return candidate;
      }
    }
    return null;
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
      // キーは正規化した追跡番号で作る。レガシーのハイフン付き履歴も
      // savedTrackings（正規化済み）と一致させ、一覧で履歴が引けるようにする。
      final key =
          '${TrackingNumberValidator.normalize(h.trackingNumber)}_${h.carrier}';
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
      // ステータスが変わっていない場合は既存レコードを更新。
      // itemType / estimatedDelivery は今回取得できなかった（null）場合、
      // 既存値を保持する（null で上書きして情報を失わない）。
      await (update(trackingHistories)
            ..where((t) => t.id.equals(latest.id)))
          .write(
        TrackingHistoriesCompanion(
          itemType: itemType == null ? const Value.absent() : Value(itemType),
          estimatedDelivery: estimatedDelivery == null
              ? const Value.absent()
              : Value(estimatedDelivery),
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

  /// 履歴保存とイベント保存を1トランザクションで行う。
  ///
  /// `saveHistory` と `saveEvents` を別々に呼ぶと、間にプロセスkillや
  /// クラッシュが挟まった場合に「新historiesだけが残りイベントが無い」
  /// 中途半端な状態になり得るため、必ず一括で実行する。
  Future<int> saveHistoryWithEvents(
    String trackingNumber,
    String carrier, {
    String? itemType,
    required String currentStatus,
    String? estimatedDelivery,
    required List<({String rawDate, String status, String? location})> events,
  }) {
    return transaction(() async {
      final historyId = await saveHistory(
        trackingNumber,
        carrier,
        itemType: itemType,
        currentStatus: currentStatus,
        estimatedDelivery: estimatedDelivery,
      );
      await saveEvents(historyId, events);
      return historyId;
    });
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
    await batch((batch) {
      // 既存イベントは常に削除する（events が空でも削除する。
      // 空データの結果でも前回のイベントが残らないようにするため）
      batch.deleteWhere(
        trackingEventEntries,
        (t) => t.historyId.equals(historyId),
      );
      if (events.isNotEmpty) {
        batch.insertAll(
          trackingEventEntries,
          events.map((e) => TrackingEventEntriesCompanion(
                historyId: Value(historyId),
                rawDate: Value(e.rawDate),
                status: Value(e.status),
                location: Value(e.location),
              )),
        );
      }
    });
  }
}
