import 'package:flutter_test/flutter_test.dart';

import 'package:trackflow/data/local/database.dart';
import 'package:trackflow/data/repositories/tracking_repository_impl.dart';
import 'package:trackflow/data/scraping/carrier_tracker.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/domain/repositories/tracking_repository.dart';
import 'package:trackflow/domain/tracking_number.dart';
import 'package:trackflow/domain/tracking_status.dart';
import 'package:trackflow/provider/background_provider.dart';

/// 指定したキャリアのみ取得成功するテストダブル。
/// ネットワークに依存せず [TrackingRepository.detectCarrierAndFetch] を検証する。
class _FakeTrackingRepository extends TrackingRepository {
  _FakeTrackingRepository(this.succeedingCarriers);

  final Set<Carrier> succeedingCarriers;
  final List<Carrier> tried = [];

  @override
  Future<TrackingInfo> fetchTracking({
    required String trackingNumber,
    required String carrier,
  }) async {
    final c = Carrier.fromString(carrier);
    tried.add(c);
    if (!succeedingCarriers.contains(c)) {
      throw const TrackerException(
        type: TrackerErrorType.notFound,
        message: '見つかりません',
      );
    }
    return TrackingInfo(
      trackingNumber: trackingNumber,
      carrier: c,
      currentStatus: '配達中',
      events: const [],
    );
  }

  @override
  bool isValidTrackingNumber(String number) =>
      TrackingNumberValidator.isValid(number);
}

void main() {
  group('TrackingRepositoryImpl', () {
    late TrackingRepositoryImpl repo;

    setUp(() {
      // isValidTrackingNumber と detectCarrier はDBを使わないため
      // インメモリDBで初期化しても安全
      repo = TrackingRepositoryImpl(AppDatabase.inMemory());
    });

    group('isValidTrackingNumber', () {
      // 有効な追跡番号
      test('11桁の数字は有効', () {
        expect(repo.isValidTrackingNumber('12345678901'), isTrue);
      });

      test('ハイフン入りの11桁は有効', () {
        expect(repo.isValidTrackingNumber('123-4567-8901'), isTrue);
      });

      test('12桁の数字は有効', () {
        expect(repo.isValidTrackingNumber('123456789012'), isTrue);
      });

      test('14桁の数字は有効', () {
        expect(repo.isValidTrackingNumber('12345678901234'), isTrue);
      });

      // 無効な追跡番号
      test('空文字は無効', () {
        expect(repo.isValidTrackingNumber(''), isFalse);
      });

      test('9桁の数字は無効', () {
        expect(repo.isValidTrackingNumber('123456789'), isFalse);
      });

      test('15桁の数字は無効', () {
        expect(repo.isValidTrackingNumber('123456789012345'), isFalse);
      });

      test('非数字を含む文字列は無効', () {
        expect(repo.isValidTrackingNumber('ABC123456789'), isFalse);
      });
    });

    group('detectCarrier', () {
      test('11桁は日本郵便と判定', () {
        expect(
          TrackingRepositoryImpl.detectCarrier('12345678901'),
          equals(Carrier.japanPost),
        );
      });

      test('13桁は日本郵便と判定', () {
        expect(
          TrackingRepositoryImpl.detectCarrier('1234567890123'),
          equals(Carrier.japanPost),
        );
      });

      test('12桁はヤマト運輸と判定', () {
        expect(
          TrackingRepositoryImpl.detectCarrier('123456789012'),
          equals(Carrier.yamato),
        );
      });

      test('ハイフン入りの12桁もヤマト運輸と判定', () {
        expect(
          TrackingRepositoryImpl.detectCarrier('1234-5678-9012'),
          equals(Carrier.yamato),
        );
      });

      test('9桁はnull', () {
        expect(
          TrackingRepositoryImpl.detectCarrier('123456789'),
          isNull,
        );
      });

      test('14桁はnull（10桁と14桁は判定対象外）', () {
        expect(
          TrackingRepositoryImpl.detectCarrier('12345678901234'),
          isNull,
        );
      });
    });
  });

  group('TrackingNumberValidator.carrierCandidates', () {
    test('10桁は佐川のみ', () {
      expect(
        TrackingNumberValidator.carrierCandidates('1234567890'),
        [Carrier.sagawa],
      );
    });

    test('11桁は日本郵便→ヤマトの順', () {
      expect(
        TrackingNumberValidator.carrierCandidates('12345678901'),
        [Carrier.japanPost, Carrier.yamato],
      );
    });

    test('12桁はヤマト→佐川→日本郵便の順', () {
      expect(
        TrackingNumberValidator.carrierCandidates('123456789012'),
        [Carrier.yamato, Carrier.sagawa, Carrier.japanPost],
      );
    });

    test('13桁は日本郵便のみ', () {
      expect(
        TrackingNumberValidator.carrierCandidates('1234567890123'),
        [Carrier.japanPost],
      );
    });

    test('14桁は全社を候補にする', () {
      expect(
        TrackingNumberValidator.carrierCandidates('12345678901234'),
        [Carrier.japanPost, Carrier.yamato, Carrier.sagawa],
      );
    });

    test('ハイフン付きでも桁数判定される', () {
      expect(
        TrackingNumberValidator.carrierCandidates('1234-5678-9012'),
        [Carrier.yamato, Carrier.sagawa, Carrier.japanPost],
      );
    });
  });

  group('TrackingRepository.detectCarrierAndFetch', () {
    test('候補順に問い合わせ、最初に成功した会社を返す', () async {
      // 12桁: ヤマト→佐川→日本郵便 の順。佐川のみ成功。
      final repo = _FakeTrackingRepository({Carrier.sagawa});

      final result = await repo.detectCarrierAndFetch('123456789012');

      expect(result?.carrier, Carrier.sagawa);
      expect(result?.info.currentStatus, '配達中');
      expect(repo.tried, [Carrier.yamato, Carrier.sagawa],
          reason: 'ヤマト失敗後に佐川で成功、日本郵便は試さない');
    });

    test('全社で見つからない場合はnull', () async {
      final repo = _FakeTrackingRepository({});

      final result = await repo.detectCarrierAndFetch('123456789012');

      expect(result, isNull);
      expect(repo.tried,
          [Carrier.yamato, Carrier.sagawa, Carrier.japanPost]);
    });

    test('10桁は佐川だけ試す', () async {
      final repo = _FakeTrackingRepository({Carrier.sagawa});

      final result = await repo.detectCarrierAndFetch('1234567890');

      expect(result?.carrier, Carrier.sagawa);
      expect(repo.tried, [Carrier.sagawa]);
    });

    test('11桁で日本郵便が成功すれば1回で確定', () async {
      final repo = _FakeTrackingRepository({Carrier.japanPost});

      final result = await repo.detectCarrierAndFetch('12345678901');

      expect(result?.carrier, Carrier.japanPost);
      expect(repo.tried, [Carrier.japanPost]);
    });
  });

  group('Carrier', () {
    test('fromStringで日本郵便を解決', () {
      expect(Carrier.fromString('japanPost'), equals(Carrier.japanPost));
    });

    test('fromStringでヤマト運輸を解決', () {
      expect(Carrier.fromString('yamato'), equals(Carrier.yamato));
    });

    test('fromStringで佐川急便を解決', () {
      expect(Carrier.fromString('sagawa'), equals(Carrier.sagawa));
    });

    test('不明な文字列はyamatoにフォールバック', () {
      expect(Carrier.fromString('unknown'), equals(Carrier.yamato));
    });

    test('displayNameが正しい', () {
      expect(Carrier.japanPost.displayName, '日本郵便');
      expect(Carrier.yamato.displayName, 'ヤマト運輸');
      expect(Carrier.sagawa.displayName, '佐川急便');
    });
  });

  group('TrackingNumberValidator.normalize', () {
    test('ハイフン付きを数字のみに正規化する', () {
      expect(
        TrackingNumberValidator.normalize('6232-0148-6493'),
        '623201486493',
      );
      expect(
        TrackingNumberValidator.normalize('123-4567-8901'),
        '12345678901',
      );
    });

    test('ハイフンなしはそのまま返る', () {
      expect(
        TrackingNumberValidator.normalize('623201486493'),
        '623201486493',
      );
    });
  });

  group('背景更新の間隔変換', () {
    test('15分が正しく変換される', () {
      expect(intervalToDuration('15分'), const Duration(minutes: 15));
    });

    test('30分が正しく変換される', () {
      expect(intervalToDuration('30分'), const Duration(minutes: 30));
    });

    test('1時間が正しく変換される', () {
      expect(intervalToDuration('1時間'), const Duration(hours: 1));
    });

    test('3時間が正しく変換される', () {
      expect(intervalToDuration('3時間'), const Duration(hours: 3));
    });

    test('未知の値は30分にフォールバック', () {
      expect(intervalToDuration('不明'), const Duration(minutes: 30));
    });
  });

  group('通知ID生成', () {
    test('同じ追跡番号には同じIDが返る', () {
      expect(notificationIdFor('12345678901'),
          notificationIdFor('12345678901'));
    });

    test('異なる追跡番号には異なるIDが返る', () {
      expect(notificationIdFor('12345678901'),
          isNot(notificationIdFor('12345678902')));
    });

    test('IDは1以上2000000000以下', () {
      final id = notificationIdFor('12345678901');
      expect(id, greaterThan(0));
      expect(id, lessThanOrEqualTo(2000000000));
    });
  });

  group('配達完了判定', () {
    test('ヤマトの配達完了', () {
      expect(isDeliveredStatus('配達完了'), isTrue);
    });

    test('佐川の配達完了', () {
      expect(isDeliveredStatus('お届け完了'), isTrue);
      expect(isDeliveredStatus('配達済み'), isTrue);
    });

    test('日本郵便のお届け済み', () {
      expect(isDeliveredStatus('お届け済み'), isTrue);
      expect(isDeliveredStatus('投函完了'), isTrue);
    });

    test('未完了ステータスはfalse', () {
      expect(isDeliveredStatus('配達中'), isFalse);
      expect(isDeliveredStatus('輸送中'), isFalse);
      expect(isDeliveredStatus('引受'), isFalse);
      expect(isDeliveredStatus(''), isFalse);
    });
  });

  group('自動更新の要否判定', () {
    test('配達完了済みは自動更新しない', () {
      expect(shouldAutoUpdate('配達完了'), isFalse);
      expect(shouldAutoUpdate('お届け済み'), isFalse);
      expect(shouldAutoUpdate('投函完了'), isFalse);
      expect(shouldAutoUpdate('配達済み'), isFalse);
      expect(shouldAutoUpdate('お届け完了'), isFalse);
    });

    test('未完了ステータスは自動更新する', () {
      expect(shouldAutoUpdate('配達中'), isTrue);
      expect(shouldAutoUpdate('輸送中'), isTrue);
      expect(shouldAutoUpdate('引受'), isTrue);
    });

    test('履歴なし（null）は初回取得のため自動更新する', () {
      expect(shouldAutoUpdate(null), isTrue);
    });

    test('空文字は自動更新する（配達完了表現を含まない）', () {
      expect(shouldAutoUpdate(''), isTrue);
    });
  });

  group('配達予定日当日判定', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    test('YYYY/MM/DD形式で今日ならtrue', () {
      final s = '${now.year}/${now.month}/${now.day}';
      expect(isDeliveryToday(s), isTrue);
    });

    test('YYYY/MM/DD形式＋曜日・時間帯付きで今日ならtrue', () {
      final s = '${now.year}/${now.month}/${now.day}（土）09:00〜11:00';
      expect(isDeliveryToday(s), isTrue);
    });

    test('年なしM/D形式で今日ならtrue', () {
      final s = '${now.month}/${now.day}（金）09:00〜11:00';
      expect(isDeliveryToday(s), isTrue);
    });

    test('昨日の日付ならfalse', () {
      final yesterday = today.subtract(const Duration(days: 1));
      expect(
        isDeliveryToday(
            '${yesterday.year}/${yesterday.month}/${yesterday.day}'),
        isFalse,
      );
      expect(
        isDeliveryToday('${yesterday.month}/${yesterday.day}'),
        isFalse,
      );
    });

    test('明日の日付ならfalse', () {
      final tomorrow = today.add(const Duration(days: 1));
      expect(
        isDeliveryToday(
            '${tomorrow.year}/${tomorrow.month}/${tomorrow.day}'),
        isFalse,
      );
      expect(
        isDeliveryToday('${tomorrow.month}/${tomorrow.day}'),
        isFalse,
      );
    });

    test('null・空文字はfalse', () {
      expect(isDeliveryToday(null), isFalse);
      expect(isDeliveryToday(''), isFalse);
    });

    test('日付を抽出できない文字列はfalse', () {
      expect(isDeliveryToday('配達予定日 未定'), isFalse);
      expect(isDeliveryToday('お届け予定なし'), isFalse);
    });

    test('年なしの年末年始は年跨ぎで判定される', () {
      // 12/31 は今日が12/31のときだけtrue（それ以外は未来→前年扱いでfalse）
      final isDec31 = now.month == 12 && now.day == 31;
      expect(isDeliveryToday('12/31'), isDec31);
      // 1/1 は今日が1/1のときだけtrue
      final isJan1 = now.month == 1 && now.day == 1;
      expect(isDeliveryToday('1/1'), isJan1);
    });

    test('月日が範囲外ならfalse（例外を投げない）', () {
      expect(isDeliveryToday('13/45'), isFalse);
      expect(isDeliveryToday('2026/13/45'), isFalse);
    });
  });

  group('AppDatabase 履歴保存', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
    });

    test('ステータスが同じ場合は履歴が増えない', () async {
      final id1 = await db.saveHistory(
        '12345678901',
        'yamato',
        currentStatus: '配達中',
      );
      final id2 = await db.saveHistory(
        '12345678901',
        'yamato',
        currentStatus: '配達中',
      );
      expect(id1, id2, reason: '同一ステータスでは既存レコードを更新すべき');

      final histories = await db.getAllLatestHistories();
      expect(histories.length, 1);
    });

    test('ステータス不変時は estimatedDelivery も最新値に更新される', () async {
      await db.saveHistory(
        '12345678901',
        'yamato',
        currentStatus: '配達中',
        estimatedDelivery: '2026/08/15',
      );
      await db.saveHistory(
        '12345678901',
        'yamato',
        currentStatus: '配達中',
        estimatedDelivery: '2026/08/16',
      );

      final history = await db.getLatestHistory('12345678901', 'yamato');
      expect(history?.estimatedDelivery, '2026/08/16');
    });

    test('ステータスが変わると新規履歴が作成される', () async {
      final id1 = await db.saveHistory(
        '12345678901',
        'yamato',
        currentStatus: '配達中',
      );
      final id2 = await db.saveHistory(
        '12345678901',
        'yamato',
        currentStatus: '配達完了',
      );
      expect(id1, isNot(id2));

      final histories = await db.getAllLatestHistories();
      expect(histories.length, 1);
      expect(histories.values.first.currentStatus, '配達完了');
    });

    test('saveEvents を2回呼んでもイベントが重複しない', () async {
      final historyId = await db.saveHistory(
        '12345678901',
        'yamato',
        currentStatus: '配達中',
      );

      await db.saveEvents(historyId, [
        (rawDate: '06/15 10:00', status: '引受', location: '東京'),
        (rawDate: '06/16 09:00', status: '配達中', location: '大阪'),
      ]);
      await db.saveEvents(historyId, [
        (rawDate: '06/15 10:00', status: '引受', location: '東京'),
        (rawDate: '06/16 09:00', status: '配達中', location: '大阪'),
      ]);

      final events = await db.getEventsForHistory(historyId);
      expect(events.length, 2, reason: '2回保存しても2件のまま');
    });

    test('getAllLatestHistories が最新ステータスを返す', () async {
      await db.saveHistory(
        '12345678901',
        'yamato',
        currentStatus: '配達中',
      );
      await db.saveHistory(
        '12345678901',
        'yamato',
        currentStatus: '配達完了',
      );

      final histories = await db.getAllLatestHistories();
      expect(histories['12345678901_yamato']?.currentStatus, '配達完了');
    });

    test('ステータス不変時は itemType が null でも既存値を保持する', () async {
      await db.saveHistory(
        '12345678901',
        'yamato',
        itemType: '宅急便',
        currentStatus: '配達中',
      );
      // 2回目は itemType を取得できなかった（null）ケースを再現
      await db.saveHistory(
        '12345678901',
        'yamato',
        currentStatus: '配達中',
      );

      final history = await db.getLatestHistory('12345678901', 'yamato');
      expect(history?.itemType, '宅急便', reason: '商品種別を失わない');
    });

    test('deleteTracking は履歴とイベントも削除する', () async {
      final savedId = await db.insertTracking('12345678901', 'yamato');
      final historyId = await db.saveHistory(
        '12345678901',
        'yamato',
        currentStatus: '配達中',
      );
      await db.saveEvents(historyId, [
        (rawDate: '06/15 10:00', status: '引受', location: '東京'),
      ]);

      await db.deleteTracking(savedId);

      expect(await db.findByTrackingNumber('12345678901', 'yamato'), isNull);
      expect(await db.getLatestHistory('12345678901', 'yamato'), isNull,
          reason: '孤児履歴が残らない');
      expect(await db.getEventsForHistory(historyId), isEmpty,
          reason: '孤児イベントが残らない');
    });

    test('deleteTracking は同一キャリアの別追跡の履歴を残す', () async {
      final saveId1 = await db.insertTracking('12345678901', 'yamato');
      await db.insertTracking('12345678902', 'yamato');
      await db.saveHistory('12345678901', 'yamato', currentStatus: '配達中');
      await db.saveHistory('12345678902', 'yamato', currentStatus: '輸送中');

      await db.deleteTracking(saveId1);

      expect(await db.getLatestHistory('12345678901', 'yamato'), isNull);
      final other = await db.getLatestHistory('12345678902', 'yamato');
      expect(other?.currentStatus, '輸送中', reason: '別追跡の履歴は残る');
    });
  });

  group('AppDatabase 追跡番号の正規化', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
    });

    test('insertTracking はハイフンを除去して保存する', () async {
      await db.insertTracking('6232-0148-6493', 'yamato');

      final saved = await db.findByTrackingNumber('6232-0148-6493', 'yamato');
      expect(saved, isNotNull);
      expect(saved!.trackingNumber, '623201486493');
    });

    test('ハイフン付きで登録しても正規化番号で重複検知される', () async {
      await db.insertTracking('623201486493', 'yamato');

      final found = await db.findByTrackingNumber('6232-0148-6493', 'yamato');
      expect(found, isNotNull, reason: 'ハイフンの有無で同一追跡と判定すべき');
    });

    test('レガシーデータ（ハイフン付き保存）も正規化番号で検索できる', () async {
      // 正規化導入前のレガシーデータはハイフン付きのまま保存されている。
      // insertTracking は正規化するため、レガシーを再現するには直接insertする。
      await db.into(db.savedTrackings).insert(
            SavedTrackingsCompanion.insert(
              trackingNumber: '6232-0148-6493',
              carrier: 'yamato',
            ),
          );

      final found = await db.findByTrackingNumber('623201486493', 'yamato');
      expect(found, isNotNull);
      expect(found!.trackingNumber, '6232-0148-6493');
    });

    test('レガシーのハイフン付き履歴も正規化番号で取得できる', () async {
      await db.saveHistory(
        '6232-0148-6493',
        'yamato',
        currentStatus: '配達中',
      );

      final history = await db.getLatestHistory('623201486493', 'yamato');
      expect(history, isNotNull);
      expect(history!.currentStatus, '配達中');
    });
  });
}
