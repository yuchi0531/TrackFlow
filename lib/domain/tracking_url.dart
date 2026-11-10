import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/tracking_number.dart';

/// 追跡入力（追跡番号そのもの、または各社の追跡URL）の解析結果。
///
/// [number] は正規化済みの追跡番号（数字のみ、エスポ便のみ `E` + 11桁）。
/// [carrierHint] は URL のホストから推定した配送会社で、推定できなければ null。
/// hint がある場合は URL の会社情報を優先する（桁数との整合性は検証しない）。
class TrackingInput {
  /// 正規化済みの追跡番号（数字のみ、またはエスポ便の `E`+11桁）
  final String number;

  /// URL から推定した配送会社（不明なら null）
  final Carrier? carrierHint;

  const TrackingInput(this.number, {this.carrierHint});

  @override
  bool operator ==(Object other) =>
      other is TrackingInput &&
      other.number == number &&
      other.carrierHint == carrierHint;

  @override
  int get hashCode => Object.hash(number, carrierHint);

  @override
  String toString() => 'TrackingInput($number, carrierHint: ${carrierHint?.name})';
}

/// 入力文字列を追跡番号・追跡URLのトークンに分割する。
///
/// 区切りは改行・カンマ・スペース（全角含む）。URL 内に区切り文字は現れないため
/// 単純分割で問題ない（`%20` などのエンコードは分割後にデコードする）。
List<String> splitTrackingTokens(String input) {
  return input
      .split(RegExp(r'[\s,、]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// 追跡番号と追跡URLが混在した入力文字列を解析する。
///
/// - URL トークンは既知のクエリパラメータ → URL 全体の数字列の順に追跡番号を探す。
///   ただし URL 全体の数字列は**既知の追跡サイトのホストに限る**（未知ホストの
///   EC 注文URL等から数字を拾って誤登録しないため）。
/// - URL でないトークンは [TrackingNumberValidator.isValid] で検証する
/// - 番号を特定できないトークンは結果に含めない（順序は保持）
/// - 重複除去は呼び出し側で行う（既存の一括追加フローを壊さないため）
List<TrackingInput> parseTrackingInputs(String input) {
  final results = <TrackingInput>[];
  for (final token in splitTrackingTokens(input)) {
    final parsed = _parseToken(token);
    if (parsed != null) results.add(parsed);
  }
  return results;
}

/// 1トークンを解析する。追跡番号として解釈できなければ null。
TrackingInput? _parseToken(String token) {
  if (_looksLikeUrl(token)) {
    return _parseUrlToken(token);
  }

  // URL でないトークンは従来どおり追跡番号として検証する
  final number = _normalizeNumber(token);
  if (!TrackingNumberValidator.isValid(number)) return null;
  return TrackingInput(number);
}

/// URL として解析する。番号が取れなければ null。
TrackingInput? _parseUrlToken(String token) {
  Uri uri;
  try {
    // スキーム省略（trackings.post.japanpost.jp/...）にも対応する
    uri = Uri.parse(token.contains('://') ? token : 'https://$token');
  } catch (_) {
    // Uri.parse は不正な形式で FormatException を投げる可能性がある
    return null;
  }

  final host = uri.host.toLowerCase();
  final hint = _carrierFromHost(host);

  // 優先: 既知のクエリパラメータ（reqCodeNo1 / number01 / okurijoNo など）。
  //        パラメータの種類から会社も推定できるため、ホストが未知でも採用する。
  // フォールバック: URL 全体の 10〜14 桁の数字列。
  //        ただし既知ホストのみ許可する。未知ホストの EC 注文URL等から数字を
  //        拾うと誤登録し、全社への問い合わせが走ってしまうため。
  final fromQuery = _fromQuery(uri, hint);
  final number = fromQuery?.number ??
      (hint != null ? _numberFromRawUrl(token, hint) : null);
  if (number == null) return null;

  // クエリパラメータの種類から推定できた会社を優先し、無ければホスト由来の
  // 推定を使う。ホスト優先にすると、ヤマトのホストに佐川のパラメータ
  // （okurijoNo）しか無い場合に「佐川の番号なのにヤマトヒント」になるため。
  // なお `_fromQuery` はホスト推定がある場合その会社のパラメータを優先して
  // 探すので、通常ケースでは両者は一致する。
  return TrackingInput(number, carrierHint: fromQuery?.carrier ?? hint);
}

/// 追跡ページのホストかどうか（スキーム省略の URL も拾うため）。
bool _looksLikeUrl(String token) {
  final lower = token.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return true;
  }
  return _knownHosts.any(lower.contains);
}

/// 追跡ページの既知ホスト（サブドメインを含む判定に使う）
const _knownHosts = [
  'japanpost.jp',
  'kuronekoyamato.co.jp',
  'sagawa-exp.co.jp',
  'espoirer.com',
];

/// ホスト名から配送会社を推定する。未知のホストは null。
///
/// `evil-kuronekoyamato.co.jp` のような偽ホストに一致しないよう、
/// `endsWith` だけでなく完全一致 or 先頭ドット付きの判定にする。
Carrier? _carrierFromHost(String host) {
  if (host == 'japanpost.jp' || host.endsWith('.japanpost.jp')) {
    return Carrier.japanPost;
  }
  if (host == 'kuronekoyamato.co.jp' ||
      host.endsWith('.kuronekoyamato.co.jp')) {
    return Carrier.yamato;
  }
  if (host == 'sagawa-exp.co.jp' || host.endsWith('.sagawa-exp.co.jp')) {
    return Carrier.sagawa;
  }
  if (host == 'espoirer.com' || host.endsWith('.espoirer.com')) {
    return Carrier.espo;
  }
  return null;
}

/// クエリパラメータのキーから配送会社を推定する（既知の追跡パラメータのみ）。
///
/// - 日本郵便: `reqCodeNo1` / `reqCodeNo2` …
/// - ヤマト運輸: `number01` …（`number00` は件数なので除外）
/// - 佐川急便: `okurijoNo` / `okurijoNo1` …
/// - エスポ便: `hawbNo` / `hawbNos` / `hawbNoList`（OWM 系の送り状番号）
Carrier? _carrierFromParamKey(String key) {
  final lower = key.toLowerCase();
  if (RegExp(r'^reqcodeno\d*$').hasMatch(lower)) return Carrier.japanPost;
  if (lower == 'number00') return null;
  if (RegExp(r'^number\d+$').hasMatch(lower)) return Carrier.yamato;
  if (RegExp(r'^okurijono\d*$').hasMatch(lower)) return Carrier.sagawa;
  if (lower == 'hawbno' || lower == 'hawbnos' || lower == 'hawbnolist') {
    return Carrier.espo;
  }
  return null;
}

/// 既知のクエリパラメータから追跡番号と配送会社を取り出す。
///
/// ホストから推定できた会社のパラメータを優先し、次に他の会社のものを走査する
/// （リダイレクトや汎用URLで会社が推定できない場合の取りこぼし対策）。
({String number, Carrier carrier})? _fromQuery(Uri uri, Carrier? hint) {
  final candidates = <(Carrier, String)>[];
  for (final entry in uri.queryParametersAll.entries) {
    final carrier = _carrierFromParamKey(entry.key);
    if (carrier == null) continue;
    for (final value in entry.value) {
      candidates.add((carrier, value));
    }
  }

  if (hint != null) {
    for (final (carrier, value) in candidates) {
      if (carrier != hint) continue;
      final number = _numberFromQueryValue(value);
      if (number != null) return (number: number, carrier: carrier);
    }
  }
  for (final (carrier, value) in candidates) {
    final number = _numberFromQueryValue(value);
    if (number != null) return (number: number, carrier: carrier);
  }
  return null;
}

/// クエリ値を正規化し、追跡番号として有効なら返す。
String? _numberFromQueryValue(String value) {
  final number = _normalizeNumber(value);
  return TrackingNumberValidator.isValid(number) ? number : null;
}

/// URL 全体から追跡番号を探すフォールバック。
///
/// **既知の追跡サイトのホストでのみ使用する**（未知ホストの URL から数字を
/// 拾うと EC の注文番号などを誤登録するため）。
/// 数字のみの番号は、件数などの短い数字を誤採用しないよう、10〜14 桁の連続
/// （前後が数字でない）に限定し、複数ある場合は最後のものを採用する
/// （追跡番号は末尾に現れることが多い）。
///
/// エスポ便の追跡URLは SPA で番号をクエリに持たないため、`E` + 11桁の英数字
/// 列（例 `E10098595043`）も抽出対象にする。
String? _numberFromRawUrl(String token, Carrier hint) {
  String decoded;
  try {
    // %2D などのエンコードを解除しておく（失敗しても元の文字列で続行する）
    decoded = Uri.decodeComponent(token);
  } catch (_) {
    decoded = token;
  }

  final cleaned = _normalizeNumber(decoded);

  if (hint == Carrier.espo) {
    // 文字列全体ではなく英数字以外で区切られた `E` + 11桁のみを拾う
    // （Dart の RegExp は lookbehind に依存しない形で書く）
    final espo = RegExp(r'(?:^|[^A-Za-z0-9])(E\d{11})(?![0-9])')
        .allMatches(cleaned)
        .map((m) => m.group(1)!)
        .toList();
    if (espo.isNotEmpty) return espo.last;
  }

  // 数字の連続（最大ラン）だけを見ることで、前後の境界判定を単純化する。
  // 15桁以上の連続は追跡番号ではないため、ランごと除外される。
  final matches = RegExp(r'\d+')
      .allMatches(cleaned)
      .map((m) => m.group(0)!)
      .where((run) => run.length >= 10 && run.length <= 14)
      .toList();
  if (matches.isEmpty) return null;
  return matches.last;
}

/// 追跡番号として扱える形に正規化する。
///
/// 挙動は [TrackingNumberValidator.normalize] に一本化する
/// （ハイフン・空白・全角スペースの除去と、エスポ便番号の大文字化）。
String _normalizeNumber(String raw) => TrackingNumberValidator.normalize(raw);
