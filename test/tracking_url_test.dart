import 'package:flutter_test/flutter_test.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/tracking_url.dart';

void main() {
  group('parseTrackingInputs - 素の追跡番号', () {
    test('11桁の数字はそのまま番号として扱われ、会社ヒントは無い', () {
      final inputs = parseTrackingInputs('12345678901');

      expect(inputs, hasLength(1));
      expect(inputs.first.number, '12345678901');
      expect(inputs.first.carrierHint, isNull);
    });

    test('ハイフン付きの番号は正規化される', () {
      final inputs = parseTrackingInputs('1234-5678-9012');

      expect(inputs.single.number, '123456789012');
      expect(inputs.single.carrierHint, isNull);
    });

    test('全角スペース区切りでも分割される', () {
      final inputs = parseTrackingInputs('12345678901\u300012345678902');

      expect(inputs.map((e) => e.number), ['12345678901', '12345678902']);
    });

    test('短すぎる数字は結果に含まれない', () {
      expect(parseTrackingInputs('123456789'), isEmpty);
    });

    test('空文字列は空リストを返す', () {
      expect(parseTrackingInputs(''), isEmpty);
      expect(parseTrackingInputs('   \n '), isEmpty);
    });
  });

  group('parseTrackingInputs - 日本郵便URL', () {
    test('reqCodeNo1 から番号を抽出し japanPost を推定する', () {
      final inputs = parseTrackingInputs(
        'https://trackings.post.japanpost.jp/services/srv/search/direct'
        '?reqCodeNo1=123456789012&searchKind=S004&locale=ja',
      );

      expect(inputs.single.number, '123456789012');
      expect(inputs.single.carrierHint, Carrier.japanPost);
    });

    test('reqCodeNo2 など複数指定時も有効な番号を拾う', () {
      final inputs = parseTrackingInputs(
        'https://trackings.post.japanpost.jp/services/srv/search/direct'
        '?reqCodeNo1=&reqCodeNo2=345678901234',
      );

      expect(inputs.single.number, '345678901234');
      expect(inputs.single.carrierHint, Carrier.japanPost);
    });

    test('クエリ値のハイフン・空白は除去される', () {
      final inputs = parseTrackingInputs(
        'https://trackings.post.japanpost.jp/services/srv/search/direct'
        '?reqCodeNo1=1234-5678-9012',
      );

      expect(inputs.single.number, '123456789012');
    });
  });

  group('parseTrackingInputs - ヤマト運輸URL', () {
    test('number01 から番号を抽出し yamato を推定する', () {
      final inputs = parseTrackingInputs(
        'https://toi.kuronekoyamato.co.jp/cgi-bin/tneko'
        '?number00=1&number01=123456789012',
      );

      expect(inputs.single.number, '123456789012');
      expect(inputs.single.carrierHint, Carrier.yamato);
    });

    test('件数を表す number00 は番号として採用しない', () {
      // number00 のみで、番号は URL 内に存在しないケース
      final inputs = parseTrackingInputs(
        'https://toi.kuronekoyamato.co.jp/cgi-bin/tneko?number00=1',
      );

      expect(inputs, isEmpty);
    });
  });

  group('parseTrackingInputs - 佐川急便URL', () {
    test('okurijoNo から番号を抽出し sagawa を推定する', () {
      final inputs = parseTrackingInputs(
        'https://k2k.sagawa-exp.co.jp/p/web/okurijosearch.do'
        '?okurijoNo=1234567890',
      );

      expect(inputs.single.number, '1234567890');
      expect(inputs.single.carrierHint, Carrier.sagawa);
    });

    test('okurijoNo1 のような揺れも受け付ける', () {
      final inputs = parseTrackingInputs(
        'https://k2k.sagawa-exp.co.jp/p/web/okurijosearch.do'
        '?okurijoNo1=1234567890',
      );

      expect(inputs.single.number, '1234567890');
      expect(inputs.single.carrierHint, Carrier.sagawa);
    });
  });

  group('parseTrackingInputs - フォールバックと耐性', () {
    test('既知ホストでクエリに番号が無い場合はURL全体から最後の10〜14桁を採用する', () {
      final inputs = parseTrackingInputs(
        'https://trackings.post.japanpost.jp/services/srv/search/direct'
        '/123456789012?searchKind=S004',
      );

      expect(inputs.single.number, '123456789012');
      expect(inputs.single.carrierHint, Carrier.japanPost);
    });

    test('短い数字が混ざっていても追跡番号だけを採用する', () {
      final inputs = parseTrackingInputs(
        'https://trackings.post.japanpost.jp/services/srv/search/direct'
        '?locale=ja&reqCodeNo1=123456789012&page=12&searchKind=S004',
      );

      expect(inputs.single.number, '123456789012');
    });

    test('未知ホストのURLからは数字列を拾わない（誤登録防止）', () {
      // EC の注文URL等を貼った場合に全社への問い合わせが走るのを防ぐ
      expect(
        parseTrackingInputs('https://example.com/orders/123456789012'),
        isEmpty,
      );
      expect(
        parseTrackingInputs('https://example.com/track/123456789012'),
        isEmpty,
      );
    });

    test('未知ホストでも既知のクエリパラメータなら番号を採用する', () {
      final inputs = parseTrackingInputs(
        'https://unknown.example.com/x?reqCodeNo1=1234567890123',
      );

      expect(inputs.single.number, '1234567890123');
      expect(inputs.single.carrierHint, Carrier.japanPost);
    });

    test('URLエンコードされたハイフン（%2D）を含む番号も抽出できる', () {
      final inputs = parseTrackingInputs(
        'https://trackings.post.japanpost.jp/services/srv/search/direct'
        '?no=1234%2D5678%2D9012',
      );

      expect(inputs.single.number, '123456789012');
    });

    test('偽ホスト（evil-kuronekoyamato.co.jp）はヤマトと判定しない', () {
      // endsWith だけで判定すると偽ホストも一致してしまう。
      // ホストが本物でなければ URL 全体からの数字列フォールバックも行わない。
      expect(
        parseTrackingInputs('https://evil-kuronekoyamato.co.jp/123456789012'),
        isEmpty,
      );
      expect(
        parseTrackingInputs('https://evil-sagawa-exp.co.jp/1234567890'),
        isEmpty,
      );
      expect(
        parseTrackingInputs('https://evil-japanpost.jp/123456789012'),
        isEmpty,
      );
    });

    test('偽ホストでもクエリパラメータの種類から推定した会社は採用する', () {
      // ホストは信用しないが、パラメータ種別からの推定は従来どおり有効
      // （未知ホストの取りこぼし対策としての既存挙動を維持する）。
      // したがって `number01` 付きの偽ヤマトホストURLでは、ホスト由来ではなく
      // パラメータ由来の yamato ヒントが付く（番号は正しく取れる）。
      final inputs = parseTrackingInputs(
        'https://evil-kuronekoyamato.co.jp/x?okurijoNo=1234567890',
      );

      expect(inputs.single.number, '1234567890');
      expect(inputs.single.carrierHint, Carrier.sagawa);
    });

    test('ホストのルートドメイン自体（サブドメイン無し）も判定できる', () {
      final inputs = parseTrackingInputs(
        'https://kuronekoyamato.co.jp/123456789012',
      );

      expect(inputs.single.number, '123456789012');
      expect(inputs.single.carrierHint, Carrier.yamato);
    });

    test('ヤマトのホストに佐川のパラメータしか無い場合はパラメータ由来の会社を使う', () {
      // ホスト優先にすると「佐川の番号なのにヤマトヒント」になり、
      // 佐川への問い合わせが走らず取得失敗するため、パラメータ種別を優先する。
      final inputs = parseTrackingInputs(
        'https://toi.kuronekoyamato.co.jp/cgi-bin/tneko?okurijoNo=1234567890',
      );

      expect(inputs.single.number, '1234567890');
      expect(inputs.single.carrierHint, Carrier.sagawa);
    });

    test('URL内に追跡番号が無ければ結果に含まれない', () {
      expect(
        parseTrackingInputs('https://trackings.post.japanpost.jp/'),
        isEmpty,
      );
    });

    test('不正なURLでもクラッシュせずスキップされる', () {
      expect(
        () => parseTrackingInputs('https://[invalid?x=123456789012'),
        returnsNormally,
      );
      expect(parseTrackingInputs('http://'), isEmpty);
    });

    test('スキーム省略の既知ホストURLも解析できる', () {
      final inputs = parseTrackingInputs(
        'trackings.post.japanpost.jp/services/srv/search/direct'
        '?reqCodeNo1=123456789012',
      );

      expect(inputs.single.number, '123456789012');
      expect(inputs.single.carrierHint, Carrier.japanPost);
    });
  });

  group('parseTrackingInputs - 混在入力', () {
    test('複数行にURLと素の番号が混在しても順序を保って解析される', () {
      final inputs = parseTrackingInputs(
        '12345678901\n'
        'https://k2k.sagawa-exp.co.jp/p/web/okurijosearch.do?okurijoNo=1234567890\n'
        'https://toi.kuronekoyamato.co.jp/cgi-bin/tneko?number00=1&number01=123456789012',
      );

      expect(inputs.map((e) => e.number), [
        '12345678901',
        '1234567890',
        '123456789012',
      ]);
      expect(inputs.map((e) => e.carrierHint), [
        null,
        Carrier.sagawa,
        Carrier.yamato,
      ]);
    });

    test('カンマ区切りでも混在入力を受け付ける', () {
      final inputs = parseTrackingInputs(
        '12345678901, https://k2k.sagawa-exp.co.jp/p/web/okurijosearch.do'
        '?okurijoNo=345678901234',
      );

      expect(inputs, hasLength(2));
      expect(inputs.last.number, '345678901234');
    });

    test('未知ホストのURLは混在入力でも結果から除外される', () {
      final inputs = parseTrackingInputs(
        '12345678901, https://example.com/track/345678901234',
      );

      expect(inputs, hasLength(1));
      expect(inputs.single.number, '12345678901');
    });
  });
}
