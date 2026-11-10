import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackflow/data/local/database.dart';
import 'package:trackflow/provider/database_provider.dart';
import 'package:trackflow/provider/tracking_providers.dart';

void main() {
  // updateWidgetSnapshot が MethodChannel を呼ぶためバインディングを初期化しておく
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrackingListNotifier.delete', () {
    late AppDatabase db;
    late ProviderContainer container;
    var dbClosed = false;

    setUp(() async {
      // updateWidgetSnapshot が SharedPreferences を読むためモック初期化が必要
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.inMemory();
      dbClosed = false;
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
        ],
      );
      // 初期化（build）を完了させてから操作する
      await container.read(trackingListProvider.future);
    });

    tearDown(() async {
      container.dispose();
      if (!dbClosed) await db.close();
    });

    test('delete すると state とDBの両方から消える', () async {
      await db.insertTracking('12345678901', 'yamato');
      await db.insertTracking('12345678902', 'yamato');
      container.invalidate(trackingListProvider);
      await container.read(trackingListProvider.future);

      expect(
        (container.read(trackingListProvider).value ?? const []).length,
        2,
      );

      await container.read(trackingListProvider.notifier).delete(
            trackingNumber: '12345678901',
            carrier: 'yamato',
          );

      final items = container.read(trackingListProvider).value ?? const [];
      expect(items.length, 1);
      expect(items.single.trackingNumber, '12345678902');
      expect(
        await db.findByTrackingNumber('12345678901', 'yamato'),
        isNull,
      );
    });

    test('存在しない番号を delete しても例外にならない', () async {
      await db.insertTracking('12345678901', 'yamato');
      container.invalidate(trackingListProvider);
      await container.read(trackingListProvider.future);

      await expectLater(
        container.read(trackingListProvider.notifier).delete(
              trackingNumber: '99999999999',
              carrier: 'yamato',
            ),
        completes,
      );

      // 既存の1件は残る
      final items = container.read(trackingListProvider).value ?? const [];
      expect(items.length, 1);
      expect(items.single.trackingNumber, '12345678901');
    });

    test('レガシーなハイフン付き保存値でも state から除去される', () async {
      // 正規化導入前のデータは getAllActive() で生のハイフン付きのまま返る。
      // 単純比較だと state から消えず「DB からだけ消える」状態になるため、
      // 正規化して照合することを確認する。
      await db.into(db.savedTrackings).insert(
            const SavedTrackingsCompanion(
              trackingNumber: Value('1234-5678-9012'),
              carrier: Value('yamato'),
            ),
          );
      container.invalidate(trackingListProvider);
      final before = await container.read(trackingListProvider.future);
      expect(before.single.trackingNumber, '1234-5678-9012');

      await container.read(trackingListProvider.notifier).delete(
            trackingNumber: '123456789012',
            carrier: 'yamato',
          );

      expect(container.read(trackingListProvider).value, isEmpty);
      expect(
        await db.findByTrackingNumber('123456789012', 'yamato'),
        isNull,
      );
    });

    test('DB削除に失敗すると一覧へ復元して例外を投げ直す', () async {
      await db.insertTracking('12345678901', 'yamato');
      await db.insertTracking('12345678902', 'yamato');
      container.invalidate(trackingListProvider);
      await container.read(trackingListProvider.future);

      // DBを閉じて削除を失敗させる（SQLITE_BUSY 等の代用）
      await db.close();
      dbClosed = true;

      await expectLater(
        container.read(trackingListProvider.notifier).delete(
              trackingNumber: '12345678901',
              carrier: 'yamato',
            ),
        throwsA(anything),
      );

      // 一覧から永久に消えず、元の位置へ戻っている
      final items = container.read(trackingListProvider).value ?? const [];
      expect(items.map((t) => t.trackingNumber).toList(),
          ['12345678902', '12345678901']);
    });
  });
}
