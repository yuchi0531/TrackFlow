import 'package:flutter_test/flutter_test.dart';

import 'package:trackflow/data/csv/csv_export.dart';
import 'package:trackflow/data/csv/csv_import.dart';
import 'package:trackflow/data/local/database.dart';

void main() {
  group('buildTrackingsCsv', () {
    test('ヘッダー行が正しい', () {
      final csv = buildTrackingsCsv(const [], const {});
      expect(
        csv.trim(),
        'trackingNumber,carrier,nickname,currentStatus,estimatedDelivery,'
        'fetchedAt',
      );
    });

    test('アクティブな追跡ごとに最新履歴が出力される', () {
      final csv = buildTrackingsCsv([
        _saved(id: 1, number: '12345678901', carrier: 'yamato', nickname: '本'),
      ], {
        '12345678901_yamato': TrackingHistory(
          id: 10,
          trackingNumber: '12345678901',
          carrier: 'yamato',
          currentStatus: '配達中',
          estimatedDelivery: '2026/08/15（土）',
          fetchedAt: DateTime(2026, 8, 13, 9, 30, 5),
        ),
      });

      final lines = csv.trim().split('\n');
      expect(lines, hasLength(2));
      expect(
        lines[1],
        '12345678901,yamato,本,配達中,2026/08/15（土）,2026-08-13 09:30:05',
      );
    });

    test('履歴がない追跡はステータス列が空になる', () {
      final csv = buildTrackingsCsv([
        _saved(
            id: 1,
            number: '1234567890123',
            carrier: 'japanPost',
            nickname: null),
      ], const {});

      final lines = csv.trim().split('\n');
      expect(lines, hasLength(2));
      expect(lines[1], '1234567890123,japanPost,,,,');
    });

    test('非アクティブな追跡は出力されない', () {
      final csv = buildTrackingsCsv([
        _saved(
            id: 1,
            number: '12345678901',
            carrier: 'yamato',
            nickname: '本',
            isActive: false),
      ], const {});

      expect(csv.trim().split('\n'), hasLength(1), reason: 'ヘッダーのみ');
    });

    test('カンマ・引用符・改行を含む値がエスケープされる', () {
      final csv = buildTrackingsCsv([
        _saved(id: 1, number: '12345678901', carrier: 'yamato', nickname: '本, 母'),
      ], {
        '12345678901_yamato': TrackingHistory(
          id: 10,
          trackingNumber: '12345678901',
          carrier: 'yamato',
          currentStatus: '配達中\n明日到着「重要」',
          estimatedDelivery: null,
          fetchedAt: DateTime(2026, 8, 13, 9, 30, 5),
        ),
      });

      // ヘッダーに続いて1データ行
      // 引用符内の改行で物理行数は増えるため、パース結果のレコード数で判定する
      expect(parseTrackingsCsv(csv), hasLength(1));
      // カンマを含む値は引用符で囲まれる
      expect(csv, contains('"本, 母"'));
      // 改行を含む値は引用符で囲まれる（1フィールドとして扱われる）
      expect(csv, contains('"配達中\n明日到着「重要」"'));
    });
  });

  group('parseTrackingsCsv', () {
    test('正常な行をパースする', () {
      const csv = 'trackingNumber,carrier,nickname\n'
          '12345678901,yamato,本\n'
          '1234567890123,japanPost,書類';

      final records = parseTrackingsCsv(csv);
      expect(records, hasLength(2));
      expect(records[0].trackingNumber, '12345678901');
      expect(records[0].carrier, 'yamato');
      expect(records[0].nickname, '本');
      expect(records[1].trackingNumber, '1234567890123');
      expect(records[1].carrier, 'japanPost');
      expect(records[1].nickname, '書類');
    });

    test('1行目のヘッダーはスキップされる', () {
      final records =
          parseTrackingsCsv('trackingNumber,carrier,nickname\n'
              '12345678901,yamato,本');
      expect(records, hasLength(1));
      expect(records.single.trackingNumber, '12345678901');
    });

    test('無効な追跡番号の行はスキップされる', () {
      const csv = 'trackingNumber,carrier,nickname\n'
          '123456789,yamato,本\n' // 9桁で無効
          '12345678901,yamato,通販';

      final records = parseTrackingsCsv(csv);
      expect(records, hasLength(1));
      expect(records.single.trackingNumber, '12345678901');
      expect(countInvalidTrackingsCsvRows(csv), 1);
    });

    test('キャリアが不一致の行はスキップされる', () {
      const csv = 'trackingNumber,carrier,nickname\n'
          '12345678901,unknown,不明\n' // 存在しないキャリア
          '12345678901,YAMATO,大文字\n' // 大文字はnameと不一致
          '12345678901,sagawa,佐川';

      final records = parseTrackingsCsv(csv);
      expect(records, hasLength(1));

      final record = records.single;
      expect(record.trackingNumber, '12345678901');
      expect(record.carrier, 'sagawa');
      expect(record.nickname, '佐川');
      expect(countInvalidTrackingsCsvRows(csv), 2);
    });

    test('引用符で囲まれたカンマ・改行を正しく処理する', () {
      const csv = 'trackingNumber,carrier,nickname\n'
          '12345678901,yamato,"本, 母"\n'
          '"123456789012",sagawa,"改行\nあり"';

      final records = parseTrackingsCsv(csv);
      expect(records, hasLength(2), reason: '改行を含む値も1レコード');
      expect(records[0].nickname, '本, 母');
      expect(records[1].trackingNumber, '123456789012');
      expect(records[1].nickname, '改行\nあり');
    });

    test('エクスポートしたCSVをラウンドトリップできる', () {
      final saved = [
        _saved(id: 1, number: '12345678901', carrier: 'yamato', nickname: '本, 母'),
        _saved(
            id: 2,
            number: '1234567890123',
            carrier: 'japanPost',
            nickname: '書類\n重要'),
      ];
      final histories = <String, TrackingHistory>{
        '12345678901_yamato': TrackingHistory(
          id: 10,
          trackingNumber: '12345678901',
          carrier: 'yamato',
          currentStatus: '配達中',
          estimatedDelivery: '2026/08/15（土）',
          fetchedAt: DateTime(2026, 8, 13, 9, 30, 5),
        ),
        '1234567890123_japanPost': TrackingHistory(
          id: 11,
          trackingNumber: '1234567890123',
          carrier: 'japanPost',
          currentStatus: 'お届け済み',
          fetchedAt: DateTime(2026, 8, 14, 12, 0, 0),
        ),
      };

      final csv = buildTrackingsCsv(saved, histories);
      final records = parseTrackingsCsv(csv);

      expect(records, hasLength(2));
      expect(records[0].trackingNumber, '12345678901');
      expect(records[0].carrier, 'yamato');
      expect(records[0].nickname, '本, 母');
      expect(records[1].trackingNumber, '1234567890123');
      expect(records[1].carrier, 'japanPost');
      expect(records[1].nickname, '書類\n重要');
    });

    test('BOM付きCSVもパースできる', () {
      final records = parseTrackingsCsv(
          '\uFEFFtrackingNumber,carrier,nickname\n'
          '12345678901,yamato,本');
      expect(records, hasLength(1));
      expect(records.single.trackingNumber, '12345678901');
      expect(records.single.nickname, '本');
    });
  });

  group('countInvalidTrackingsCsvRows', () {
    test('空行は無効として数えない', () {
      const csv = 'trackingNumber,carrier,nickname\n'
          '\n'
          '12345678901,yamato,本\n'
          '1234,unknown,不明\n'; // 無効: 番号9桁未満＋キャリア不一致

      expect(countInvalidTrackingsCsvRows(csv), 1);
    });

    test('ヘッダーのみの場合は0', () {
      expect(
        countInvalidTrackingsCsvRows('trackingNumber,carrier,nickname'),
        0,
      );
    });
  });
}

SavedTracking _saved({
  required int id,
  required String number,
  required String carrier,
  required String? nickname,
  bool isActive = true,
}) {
  return SavedTracking(
    id: id,
    trackingNumber: number,
    carrier: carrier,
    nickname: nickname,
    isActive: isActive,
    createdAt: DateTime(2026, 8, 1),
  );
}