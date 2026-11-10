import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:trackflow/core/constants/carrier_urls.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/entities/tracking_event.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/domain/tracking_number.dart';

import 'carrier_tracker.dart';

/// エスポ便（ESPエクスプレス / ESPOIRER）の追跡トラッカー
///
/// 追跡ページは React SPA で HTML から情報を取れないため、ページが内部で
/// 呼び出している JSON API（`POST /prod/other/status`、認証不要）を利用する。
class EspoTracker implements CarrierTracker {
  @override
  String get carrierId => 'espo';

  @override
  Future<TrackingInfo> fetch(String trackingNumber) async {
    final uri = Uri.parse(CarrierUrls.espoTrackingUrl);

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': CarrierUrls.userAgent,
              'Origin': 'https://www.console.espoirer.com',
            },
            body: jsonEncode({
              'hawbNoList': [trackingNumber],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw TrackerException(
          type: TrackerErrorType.networkFailure,
          message: 'HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      // parse は「レスポンス本文の文字列」を受け取る契約のため、
      // 日本語を含むステータスを取りこぼさないよう utf8 でデコードして渡す。
      return parse(utf8.decode(response.bodyBytes), trackingNumber);
    } on TrackerException {
      rethrow;
    } on Exception catch (e) {
      throw TrackerException(
        type: TrackerErrorType.networkFailure,
        message: 'サーバーに接続できません: $e',
      );
    }
  }

  @override
  TrackingInfo parse(String json, String trackingNumber) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      throw const TrackerException(
        type: TrackerErrorType.parseFailure,
        message: 'レスポンスのJSON解析に失敗しました',
      );
    }

    final root = decoded is Map<String, dynamic> ? decoded : null;
    if (root == null) {
      throw const TrackerException(
        type: TrackerErrorType.parseFailure,
        message: 'レスポンスのJSON解析に失敗しました',
      );
    }

    // errcode は 0 が正常。非0 は API 側の異常なので notFound と区別する
    // （notFound にすると「番号が無い」と誤って案内してしまう）。
    // 実 API の型は int だが、文字列（"500" 等）で返る可能性もあるため
    // 数値として解釈できる場合は非0判定を行う。
    final errcode = root['errcode'];
    final errcodeValue = errcode is int
        ? errcode
        : (errcode is String ? int.tryParse(errcode) : null);
    if (errcodeValue != null && errcodeValue != 0) {
      throw TrackerException(
        type: TrackerErrorType.networkFailure,
        message: 'エスポ便APIエラー（errcode: $errcode）',
      );
    }

    final result = root['result'];
    if (result is! List || result.isEmpty) {
      throw TrackerException(
        type: TrackerErrorType.notFound,
        message: 'お問い合わせ番号が見つかりません',
      );
    }

    // 1番号だけ送っているので通常は1要素だが、複数返る場合に備えて
    // 送信した番号と hawbNo が一致する要素を優先する（別荷物の履歴を出さない）。
    // hawbNo が無い/一致しない場合は先頭要素にフォールバックする。
    final normalizedTarget = TrackingNumberValidator.normalize(trackingNumber);
    Map<String, dynamic>? item;
    for (final element in result) {
      if (element is! Map<String, dynamic>) continue;
      final hawbNo = element['hawbNo'];
      if (hawbNo is String &&
          TrackingNumberValidator.normalize(hawbNo) == normalizedTarget) {
        item = element;
        break;
      }
    }
    if (item == null) {
      for (final element in result) {
        if (element is Map<String, dynamic>) {
          item = element;
          break;
        }
      }
    }
    if (item == null) {
      throw const TrackerException(
        type: TrackerErrorType.parseFailure,
        message: 'レスポンスの形式が想定と異なります',
      );
    }

    final orderTracks = item['orderTrackVoList'];
    if (orderTracks is! List) {
      // イベントが無い場合は「該当なし」と同じ扱いにする。
      // 実 API はイベントが無い荷物に 901/902 等の推定コードを返す設計だが、
      // 本アプリではステータスを表示できないため notFound として扱う（簡略化）。
      throw TrackerException(
        type: TrackerErrorType.notFound,
        message: '追跡履歴が見つかりません',
      );
    }

    // orderTrackType == 5 は画面側（JS）でも除外している内部用コード
    final events = <_DatedEvent>[];
    for (var i = 0; i < orderTracks.length; i++) {
      final entry = orderTracks[i];
      if (entry is! Map<String, dynamic>) continue;

      final type = entry['orderTrackType'];
      if (type is! int || type == 5) continue;

      final rawTime = entry['createTime'];
      if (rawTime is! String) continue;
      // ISO8601（2024-07-24T14:35:28Z）と `yyyy-MM-dd HH:mm:ss` の両方を
      // DateTime.tryParse が解釈できる。`Z` 付きは UTC なので端末の
      // ローカル時刻へ変換し、一覧の「〇分前」表示や日付がずれないようにする。
      final parsed = DateTime.tryParse(rawTime);
      if (parsed == null) continue;
      final date = parsed.toLocal();

      events.add(
        _DatedEvent(
          date: date,
          status: _statusLabel(type),
          index: i,
        ),
      );
    }

    if (events.isEmpty) {
      throw TrackerException(
        type: TrackerErrorType.notFound,
        message: '追跡履歴が見つかりません',
      );
    }

    // 表示順は「古い順」（TrackingInfo.events の契約）。
    // 秒精度の同一時刻イベントでも順序が揺れないよう、元配列の index を
    // 副キーにした安定ソートを行う（非安定 sort だと currentStatus が不定になる）。
    events.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.index.compareTo(b.index);
    });

    final shippingClub = item['shippingClub'];

    return TrackingInfo(
      trackingNumber: trackingNumber,
      carrier: Carrier.espo,
      // 商品種別の代わりに転送先の配送業者を表示する（国内配送の確認に有用）
      itemType: shippingClub is String && shippingClub.isNotEmpty
          ? '転送: $shippingClub'
          : null,
      currentStatus: events.last.status,
      // エスポ便の API は配達予定日を返さない
      estimatedDelivery: null,
      events: [
        for (final e in events)
          TrackingEvent(
            rawDate: _formatDate(e.date),
            date: e.date,
            status: e.status,
            // レスポンスに拠点名に相当する有用なフィールドが無いため null
            location: null,
          ),
      ],
      lastUpdated: DateTime.now(),
    );
  }

  /// `yyyy/MM/dd HH:mm` 形式に整える（ISO8601 の `T` や `Z` を避ける）。
  static String _formatDate(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}/${two(date.month)}/${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  /// ステータスコードを日本語文言に変換する（未登録コードはフォールバック）。
  static String _statusLabel(int code) =>
      _statusLabels[code] ?? '確認中（コード: $code）';

  /// エスポ便のステータスコード → 日本語文言
  ///
  /// 追跡ページの ja-JP ロケール定義
  /// （`expressTrackingPage.content.otherDelivery.status.<code>`）に準拠する。
  static const Map<int, String> _statusLabels = {
    // 自社配送（国内）
    101: '集荷',
    102: '輸送中',
    103: '配達中',
    104: '配達完了',
    105: 'ご不在',
    106: '持戻り',
    107: '保管中',
    108: '配達完了【宅配BOX】',
    109: '営業所受取',
    110: '定休日',
    111: 'お申込【受取先変更】',
    112: '受取場所保管中【受取先変更】',
    113: '宅配BOX利用不可',
    114: 'キャンセル【受取先変更】',
    115: '引渡完了【受取先変更】',
    116: '配達中【受取先変更】',
    117: 'お問合せ',
    118: 'ロッカー空き無し【受取先変更】',
    119: '営業所保管中【受取先変更】',
    120: '該当なし',
    121: '受取先変更不可【受取先変更】',
    122: '一部配達完了',
    123: '確認中【受取先変更】',
    124: '派送中',
    // 日本郵便系（転送）
    201: '引受',
    202: '引受 大口',
    203: '委託引受',
    204: '再差出',
    205: '引受確定（予約運用）',
    206: '引受確定（確定運用）',
    207: '予約運用（書留受領証）',
    208: '局内受取',
    209: '委託引渡',
    210: '通過',
    211: '無集配送付',
    212: 'コンビニ引渡',
    213: 'はこぽす等入庫',
    214: '車船輸送 品名未記載',
    215: '車船輸送 具体的品名なし',
    220: '到着',
    221: '持出',
    222: '持出 大口',
    223: '不在 持ち戻り',
    224: '不在 代人配達',
    225: '不在 指定場所',
    226: '不在 ムツ',
    227: '配達完了',
    228: '配達完了 代人配達',
    229: '配達完了 指定場所',
    230: '配達完了 返還完了',
    231: '配達完了 委託先',
    232: '配達完了 受取',
    233: '窓口交付',
    234: '局内交付',
    235: '不在留置',
    236: '保管 私書箱',
    237: '保管 局留',
    238: '保管 指示待ち',
    239: '保管 棚入',
    240: '保管 棚出',
    241: '保管 その他',
    242: '転送 受取場所変更',
    243: '転送 転居',
    244: '転送 あて名変更',
    245: '転送 嘱託回送',
    246: '転送 海外転送',
    247: '転送 その他',
    248: '返還 汚損・き損',
    249: '返還 期間経過',
    250: '返還 転送期間経過',
    251: '返還 たずねあたらず',
    252: '返還 あて名不完全',
    253: '返還 棟室番号無',
    254: '返還 受取拒絶',
    255: '返還 取り戻し',
    256: '返還 転送不要',
    257: '返還 転居先不明',
    258: '返還 返還不要',
    259: '返還 返還不能',
    260: '返還 長期不在',
    261: '返還 その他',
    262: '配達希望',
    263: '転送希望',
    264: '保管期間延長',
    265: '取り戻し希望',
    266: '返還取り消し',
    267: '留置希望',
    268: '初回配達希望',
    269: '初回転送希望',
    270: '初回留置希望',
    271: '配達予定 休業日',
    272: '配達予定 災害',
    273: '配達予定 業務都合',
    274: '配達予定 その他',
    // ヤマト運輸系（転送）
    301: '荷物受付',
    302: '発送',
    303: '配達完了',
    304: '依頼受付（日·時間帯変更）',
    305: '配達日·時間帯指定（保管中）',
    306: '持戻（ご不在）',
    307: '依頼受付（再配達）',
    308: '作業店通過',
    309: '配達予定',
    310: '持戻（転居）',
    311: '保管中',
    312: '調査中',
    313: '配達完了（宅配ボックス）',
    315: 'ご来店予定（保管中）',
    316: '持戻',
    320: '配達担当店保管中',
    321: '持戻（休業）',
    325: '転送',
    331: '配達中',
    332: '返品（持戻保管中）',
    333: '返品',
    335: '返品完了',
    337: '配達担当営業所保管中',
    341: '通過',
    342: '発送済み',
    343: '輸送中',
    347: '一時保管中',
    348: 'お客様引渡完了',
    350: '転送／返品',
    352: '配達店到着',
    355: '持ち出し中',
    356: '配達準備中',
    357: '宅配ボックスお届け準備',
    362: '海外荷物受付',
    363: '海外発送',
    364: '国内到着',
    365: '投函完了',
    366: '発送中止',
    // 佐川急便系（転送）
    401: '荷物受付',
    402: '税関審査',
    403: '最寄りの配送拠点へ移動中',
    404: '税関許可',
    405: '最寄りの配送拠点に到着',
    406: 'ラップスキャン',
    407: '配達中',
    408: '配達完了',
    409: '配達',
    410: '配送失敗 アドレスエラー',
    411: '小包の紛失',
    412: '配送失敗のその他の理由',
    413: '納品失敗 倉庫への返品',
    414: '配達失敗後30日間倉庫に保管',
    416: '小包の廃棄',
    417: '顧客引出し',
    418: '配達完了',
    420: 'コースエラー',
    421: '二次配送',
    422: 'スキャンされて返品された小包',
    423: '納品された小包は顧客に拒否されました',
    424: '二次配送',
    426: '小包を第三者に転送',
    427: '小包はサービスポイントで受け取る準備ができています',
    428: '再配達完了',
    430: '差出人倉庫に戻る',
    431: '配送失敗, 後で再試行してください',
    433: '配達中',
    434: '無効なアドレスは送信できません',
    // 国際輸送系
    501: '荷物受付',
    502: '注文がキャンセルされました',
    503: '荷物受付',
    504: '最寄りの配送拠点へ移動中',
    505: '最寄りの配送拠点に到着',
    506: '配達中',
    507: '荷物が仕分けセンターへ返送されました',
    508: '貨物が営業所へ返送されました',
    509: 'お客様へ返送済み',
    510: '国内中継輸送中',
    511: '輸出通関手続き中',
    512: '輸出通関失敗',
    513: '輸出通関完了',
    514: '出発地の空港／港を出発しました',
    515: '貨物が航空会社へ引き渡されました',
    516: '到着国の空港／港に到着しました',
    517: '税関で保留されています',
    518: '税関保留 - 受取人による関税確認が必要',
    519: '税関保留 - 有効な納税者番号が必要',
    520: '税関保留 - 検疫検査待ち',
    521: '税関保留 - 税関の許可待ち',
    522: '税関保留 - 受取人情報が必要',
    523: '到着国で通関手続き中',
    524: '到着国で通関完了',
    525: '目的地での中継輸送中',
    526: '配達中',
    527: '住所不明',
    528: '受取待ち',
    529: '配送失敗',
    530: '返送中',
    531: '紛失',
    532: 'その他の異常',
    533: '配達完了',
    534: 'USPS輸送中',
    // 伝票未登録
    901: '伝票番号未登録',
    902: '伝票番号未登録',
  };
}

/// ソート用のイベント（日時・ステータス・元配列の位置）。
///
/// 同一秒に複数イベントがあると非安定な `List.sort` では順序が不定になり
/// `currentStatus`（= 最後の要素）が揺れるため、元配列の `index` を副キーにする。
class _DatedEvent {
  final DateTime date;
  final String status;
  final int index;

  const _DatedEvent({
    required this.date,
    required this.status,
    required this.index,
  });
}
