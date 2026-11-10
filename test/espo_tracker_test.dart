import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:trackflow/data/scraping/carrier_tracker.dart';
import 'package:trackflow/data/scraping/espo_tracker.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/tracking_status.dart';

/// 実 API（`POST /prod/other/status`）のレスポンス形状を再現したフィクスチャ。
///
/// `E10098595043` は実際に取得したレスポンスを基にした形状。実 API は
/// リクエストを `{"data":{"hawbNoList":[...]}}` とラップして送る必要があるが、
/// **レスポンスはラップされていない**（`result` がルート直下）。
String _fixtureJson({
  List<Map<String, Object?>>? orderTracks,
  String shippingClub = 'エスポ便',
  String inOutType = '0',
}) {
  final tracks =
      orderTracks ??
      [
        {
          'orderTrackType': 5001,
          'createTime': '2026-11-10 21:38:45',
          'orderStatus': '集荷',
        },
      ];

  return jsonEncode({
    'responseMetaData': null,
    'errcode': 0,
    'result': [
      {
        'hawbNo': 'E10098595043',
        'trackingNo': 'E10098595043',
        'shippingClub': shippingClub,
        'inOutType': inOutType,
        'shipmentRegistered': '2026-11-06T00:59:34.000+0000',
        'decl': '2026/11/10 14:15:42',
        'moveInTime': '2026/11/10 14:15:26',
        'orderTrackVoList': tracks,
      },
    ],
  });
}

void main() {
  group('EspoTracker.parse', () {
    final tracker = EspoTracker();

    test('carrierId は espo', () {
      expect(tracker.carrierId, 'espo');
    });

    test('実レスポンス（5001 / orderStatus: 集荷）から events と currentStatus を作る', () {
      final info = tracker.parse(_fixtureJson(), 'E10098595043');

      expect(info.carrier, Carrier.espo);
      expect(info.trackingNumber, 'E10098595043');
      expect(info.events, hasLength(1));
      expect(info.events.first.status, '集荷');
      expect(info.events.first.date, DateTime(2026, 11, 10, 21, 38, 45));
      expect(info.currentStatus, '集荷');
      expect(info.estimatedDelivery, isNull);
    });

    test('実データ相当の3イベント（集荷→持ち出し→配達完了）で最新が配達完了', () {
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {
              'orderTrackType': 5001,
              'createTime': '2026-11-10 08:00:00',
              'orderStatus': '集荷',
            },
            {
              'orderTrackType': 5003,
              'createTime': '2026-11-10 14:15:00',
              'orderStatus': '持ち出し',
            },
            {
              'orderTrackType': 5007,
              'createTime': '2026-11-10 18:30:00',
              'orderStatus': '配達完了',
            },
          ],
        ),
        'E10098595043',
      );

      expect(info.carrier, Carrier.espo);
      expect(info.events.map((e) => e.status), ['集荷', '持ち出し', '配達完了']);
      expect(info.currentStatus, '配達完了');
      expect(isDeliveredStatus(info.currentStatus), isTrue);
    });

    test('orderStatus が 配送完了 なら isDeliveredStatus が true', () {
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {
              'orderTrackType': 5007,
              'createTime': '2026-11-10 18:30:00',
              'orderStatus': '配送完了',
            },
          ],
        ),
        'E10098595043',
      );

      expect(info.currentStatus, '配送完了');
      expect(isDeliveredStatus(info.currentStatus), isTrue);
    });

    test('orderStatus が null ならコードから文言を引く（5023 → 輸送中）', () {
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {
              'orderTrackType': 5023,
              'createTime': '2026-11-10 12:00:00',
              'orderStatus': null,
            },
          ],
        ),
        'E10098595043',
      );

      expect(info.currentStatus, '輸送中');
    });

    test('orderStatus が空文字ならコードから文言を引く', () {
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {
              'orderTrackType': 5003,
              'createTime': '2026-11-10 12:00:00',
              'orderStatus': '  ',
            },
          ],
        ),
        'E10098595043',
      );

      expect(info.currentStatus, '持ち出し');
    });

    test('itemType に転送先の配送業者（shippingClub）が入る', () {
      final info = tracker.parse(_fixtureJson(), 'E10098595043');

      expect(info.itemType, '転送: エスポ便');
    });

    test('shippingClub が無ければ itemType は null', () {
      final json = jsonEncode({
        'errcode': 0,
        'result': [
          {
            'hawbNo': 'E10098595043',
            'orderTrackVoList': [
              {
                'orderTrackType': 5001,
                'createTime': '2026-11-10 21:38:45',
                'orderStatus': '集荷',
              },
            ],
          },
        ],
      });

      final info = tracker.parse(json, 'E10098595043');

      expect(info.itemType, isNull);
    });

    test('ISO8601（T区切り）と yyyy-MM-dd HH:mm:ss の両方を解釈する', () {
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {
              'orderTrackType': 5001,
              'createTime': '2026-11-10 08:00:00',
              'orderStatus': '集荷',
            },
            {
              'orderTrackType': 5003,
              'createTime': '2026-11-10T14:15:00',
              'orderStatus': '持ち出し',
            },
          ],
        ),
        'E10098595043',
      );

      expect(info.events, hasLength(2));
      expect(info.events.first.date, DateTime(2026, 11, 10, 8));
      expect(info.events.last.date, DateTime(2026, 11, 10, 14, 15));
    });

    test('orderTrackType: 5 の要素は除外される', () {
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {
              'orderTrackType': 5001,
              'createTime': '2026-11-10 08:00:00',
              'orderStatus': '集荷',
            },
            {'orderTrackType': 5, 'createTime': '2026-11-10 09:00:00'},
            {
              'orderTrackType': 5003,
              'createTime': '2026-11-10 14:15:00',
              'orderStatus': '持ち出し',
            },
          ],
        ),
        'E10098595043',
      );

      expect(info.events, hasLength(2));
      expect(info.events.map((e) => e.status), ['集荷', '持ち出し']);
    });

    test('createTime が不正な要素は除外される', () {
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {'orderTrackType': 5001, 'createTime': 'not-a-date'},
            {
              'orderTrackType': 5003,
              'createTime': '2026-11-10 14:15:00',
              'orderStatus': '持ち出し',
            },
          ],
        ),
        'E10098595043',
      );

      expect(info.events, hasLength(1));
      expect(info.currentStatus, '持ち出し');
    });

    test('result が空配列なら notFound', () {
      final json = jsonEncode({
        'responseMetaData': null,
        'errcode': 0,
        'result': <Object>[],
      });

      expect(
        () => tracker.parse(json, 'E10098595043'),
        throwsA(
          isA<TrackerException>().having(
            (e) => e.type,
            'type',
            TrackerErrorType.notFound,
          ),
        ),
      );
    });

    test('result が null なら notFound', () {
      final json = jsonEncode({'errcode': 0, 'result': null});

      expect(
        () => tracker.parse(json, 'E10098595043'),
        throwsA(
          isA<TrackerException>().having(
            (e) => e.type,
            'type',
            TrackerErrorType.notFound,
          ),
        ),
      );
    });

    test('orderTrackVoList が null なら notFound（存在しない番号の実レスポンス）', () {
      // 存在しない番号でも HTTP 200 / errcode 0 で返り、全フィールド null の
      // 要素が1件入る（空配列ではない）。イベントが無いので notFound とする。
      final json = jsonEncode({
        'responseMetaData': null,
        'errcode': 0,
        'result': [
          {
            'hawbNo': null,
            'trackingNo': null,
            'shippingClub': null,
            'inOutType': null,
            'shipmentRegistered': null,
            'orderTrackVoList': null,
          },
        ],
      });

      expect(
        () => tracker.parse(json, 'E10098595043'),
        throwsA(
          isA<TrackerException>().having(
            (e) => e.type,
            'type',
            TrackerErrorType.notFound,
          ),
        ),
      );
    });

    test('イベントが空なら notFound（ステータスを表示できないため）', () {
      final info = _fixtureJson(
        orderTracks: [
          {'orderTrackType': 5, 'createTime': '2026-11-10 09:00:00'},
        ],
      );

      expect(
        () => tracker.parse(info, 'E10098595043'),
        throwsA(
          isA<TrackerException>().having(
            (e) => e.type,
            'type',
            TrackerErrorType.notFound,
          ),
        ),
      );
    });

    test('不正な JSON なら parseFailure', () {
      expect(
        () => tracker.parse('<html>not json</html>', 'E10098595043'),
        throwsA(
          isA<TrackerException>().having(
            (e) => e.type,
            'type',
            TrackerErrorType.parseFailure,
          ),
        ),
      );
    });

    test('errcode が非0なら networkFailure（notFound と混同しない）', () {
      final json = jsonEncode({
        'responseMetaData': null,
        'errcode': 500,
        'result': <Object>[],
      });

      expect(
        () => tracker.parse(json, 'E10098595043'),
        throwsA(
          isA<TrackerException>().having(
            (e) => e.type,
            'type',
            TrackerErrorType.networkFailure,
          ),
        ),
      );
    });

    test('errcode が文字列の非0でも networkFailure', () {
      final json = jsonEncode({
        'responseMetaData': null,
        'errcode': '500',
        'result': <Object>[],
      });

      expect(
        () => tracker.parse(json, 'E10098595043'),
        throwsA(
          isA<TrackerException>().having(
            (e) => e.type,
            'type',
            TrackerErrorType.networkFailure,
          ),
        ),
      );
    });

    test('result が複数要素なら送信した hawbNo の荷物を採用する', () {
      final json = jsonEncode({
        'errcode': 0,
        'result': [
          {
            'hawbNo': 'E99999999999',
            'orderTrackVoList': [
              {
                'orderTrackType': 5007,
                'createTime': '2026-11-08 09:00:00',
                'orderStatus': '配達完了',
              },
            ],
          },
          {
            'hawbNo': 'E10098595043',
            'orderTrackVoList': [
              {
                'orderTrackType': 5001,
                'createTime': '2026-11-10 08:00:00',
                'orderStatus': '集荷',
              },
              {
                'orderTrackType': 5003,
                'createTime': '2026-11-10 14:15:00',
                'orderStatus': '持ち出し',
              },
            ],
          },
        ],
      });

      final info = tracker.parse(json, 'E10098595043');

      // 先頭（別番号）の「配達完了」ではなく、対象番号の履歴になる
      expect(info.currentStatus, '持ち出し');
      expect(info.events, hasLength(2));
    });

    test('同一 createTime でも元の配列順で安定ソートされる', () {
      const sameTime = '2026-11-10 18:30:00';
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {
              'orderTrackType': 5001,
              'createTime': sameTime,
              'orderStatus': '集荷',
            },
            {
              'orderTrackType': 5003,
              'createTime': sameTime,
              'orderStatus': '持ち出し',
            },
          ],
        ),
        'E10098595043',
      );

      // index を副キーにしているので、後ろにある 5003（持ち出し）が最新になる
      expect(info.events.map((e) => e.status), ['集荷', '持ち出し']);
      expect(info.currentStatus, '持ち出し');
    });
  });

  group('EspoTracker ステータスコードの日本語化', () {
    final tracker = EspoTracker();

    /// orderStatus を持たない（= コードのみ）イベントで文言を確認する。
    String statusOf(int code) {
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {'orderTrackType': code, 'createTime': '2026-11-10 18:30:00'},
          ],
        ),
        'E10098595043',
      );
      return info.currentStatus;
    }

    test('5000番台（現行形式）が日本語になる', () {
      expect(statusOf(5001), '集荷');
      expect(statusOf(5002), '配達中');
      expect(statusOf(5003), '持ち出し');
      expect(statusOf(5007), '配達完了');
      expect(statusOf(5010), '返品完了');
      expect(statusOf(5023), '輸送中');
      expect(statusOf(5031), '積込失敗-その他');
    });

    test('3桁コード（旧形式）も維持されている', () {
      expect(statusOf(101), '集荷');
      expect(statusOf(103), '配達中');
      expect(statusOf(201), '引受');
      expect(statusOf(303), '配達完了');
    });

    test('未登録コードはフォールバック文言になる', () {
      expect(statusOf(9999), '確認中（コード: 9999）');
    });
  });
}
