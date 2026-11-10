import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:trackflow/data/scraping/carrier_tracker.dart';
import 'package:trackflow/data/scraping/espo_tracker.dart';
import 'package:trackflow/domain/entities/carrier.dart';

/// 実 API（`POST /prod/other/status`）のレスポンス形状を再現したフィクスチャ。
///
/// `E10098595043` はユーザー指定の実在する追跡番号（現在はデータ保持期限切れで
/// 実 API は `result: []` を返す）。ここでは実際にデータが返る場合の形状を再現する。
String _fixtureJson({
  List<Map<String, Object?>>? orderTracks,
  String shippingClub = 'YAMATO',
}) {
  final tracks =
      orderTracks ??
      [
        {
          'orderTrackType': 101,
          'createTime': '2024-07-22 10:15:30',
          'orderStatus': '集荷',
        },
        {
          'orderTrackType': 102,
          'createTime': '2024-07-23 08:05:00',
          'orderStatus': '輸送中',
        },
        {
          'orderTrackType': 103,
          'createTime': '2024-07-24T14:35:28',
          'orderStatus': '配達中',
        },
      ];

  return jsonEncode({
    'responseMetaData': null,
    'errcode': 0,
    'result': [
      {
        'hawbNo': 'E10098595043',
        'trackingNo': '623201486493',
        'shippingClub': shippingClub,
        'inOutType': '1',
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

    test('追跡イベントを古い順に3件返し、最新を currentStatus にする', () {
      final info = tracker.parse(_fixtureJson(), 'E10098595043');

      expect(info.carrier, Carrier.espo);
      expect(info.trackingNumber, 'E10098595043');
      expect(info.events, hasLength(3));
      // 古い順（TrackingInfo.events の契約）
      expect(info.events.map((e) => e.status), ['集荷', '輸送中', '配達中']);
      expect(info.events.map((e) => e.date), [
        DateTime(2024, 7, 22, 10, 15, 30),
        DateTime(2024, 7, 23, 8, 5),
        DateTime(2024, 7, 24, 14, 35, 28),
      ]);
      expect(info.currentStatus, '配達中');
      expect(info.estimatedDelivery, isNull);
    });

    test('itemType に転送先の配送業者（shippingClub）が入る', () {
      final info = tracker.parse(_fixtureJson(), 'E10098595043');

      expect(info.itemType, contains('YAMATO'));
    });

    test('shippingClub が無ければ itemType は null', () {
      final json = jsonEncode({
        'errcode': 0,
        'result': [
          {
            'hawbNo': 'E10098595043',
            'orderTrackVoList': [
              {'orderTrackType': 101, 'createTime': '2024-07-22 10:15:30'},
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
            {'orderTrackType': 101, 'createTime': '2024-07-22 10:15:30'},
            {'orderTrackType': 103, 'createTime': '2024-07-24T14:35:28'},
          ],
        ),
        'E10098595043',
      );

      expect(info.events, hasLength(2));
      expect(info.events.first.date, DateTime(2024, 7, 22, 10, 15, 30));
      expect(info.events.last.date, DateTime(2024, 7, 24, 14, 35, 28));
    });

    test('orderTrackType: 5 の要素は除外される', () {
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {'orderTrackType': 101, 'createTime': '2024-07-22 10:15:30'},
            {'orderTrackType': 5, 'createTime': '2024-07-23 09:00:00'},
            {'orderTrackType': 103, 'createTime': '2024-07-24 14:35:28'},
          ],
        ),
        'E10098595043',
      );

      expect(info.events, hasLength(2));
      expect(info.events.map((e) => e.status), ['集荷', '配達中']);
    });

    test('createTime が不正な要素は除外される', () {
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {'orderTrackType': 101, 'createTime': 'not-a-date'},
            {'orderTrackType': 103, 'createTime': '2024-07-24 14:35:28'},
          ],
        ),
        'E10098595043',
      );

      expect(info.events, hasLength(1));
      expect(info.currentStatus, '配達中');
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

    test('イベントが空なら notFound（ステータスを表示できないため）', () {
      final info = _fixtureJson(
        orderTracks: [
          {'orderTrackType': 5, 'createTime': '2024-07-23 09:00:00'},
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
              {'orderTrackType': 104, 'createTime': '2024-07-20 09:00:00'},
            ],
          },
          {
            'hawbNo': 'E10098595043',
            'orderTrackVoList': [
              {'orderTrackType': 101, 'createTime': '2024-07-22 10:15:30'},
              {'orderTrackType': 103, 'createTime': '2024-07-24 14:35:28'},
            ],
          },
        ],
      });

      final info = tracker.parse(json, 'E10098595043');

      // 先頭（別番号）の「配達完了」ではなく、対象番号の履歴になる
      expect(info.currentStatus, '配達中');
      expect(info.events, hasLength(2));
    });

    test('同一 createTime でも元の配列順で安定ソートされる', () {
      const sameTime = '2024-07-24 14:35:28';
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {'orderTrackType': 101, 'createTime': sameTime},
            {'orderTrackType': 103, 'createTime': sameTime},
          ],
        ),
        'E10098595043',
      );

      // index を副キーにしているので、後ろにある 103（配達中）が最新になる
      expect(info.events.map((e) => e.status), ['集荷', '配達中']);
      expect(info.currentStatus, '配達中');
    });
  });

  group('EspoTracker ステータスコードの日本語化', () {
    final tracker = EspoTracker();

    String statusOf(int code) {
      final info = tracker.parse(
        _fixtureJson(
          orderTracks: [
            {'orderTrackType': code, 'createTime': '2024-07-24 14:35:28'},
          ],
        ),
        'E10098595043',
      );
      return info.currentStatus;
    }

    test('主要コードが日本語になる', () {
      expect(statusOf(101), '集荷');
      expect(statusOf(103), '配達中');
      expect(statusOf(104), '配達完了');
      expect(statusOf(201), '引受');
      expect(statusOf(303), '配達完了');
      expect(statusOf(348), 'お客様引渡完了');
      expect(statusOf(501), '荷物受付');
      expect(statusOf(513), '輸出通関完了');
      expect(statusOf(533), '配達完了');
    });

    test('未登録コードはフォールバック文言になる', () {
      expect(statusOf(9999), '確認中（コード: 9999）');
    });
  });
}
