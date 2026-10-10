import 'package:trackflow/domain/entities/carrier.dart';

/// 追跡番号の検証とキャリア自動判別を行うドメイン層ユーティリティ。
///
/// Presentation 層から Repository の実装クラスに依存しないよう、
/// 純粋な静的処理を domain 層へ分離した。
class TrackingNumberValidator {
  /// 追跡番号からハイフンを除去して正規化する（数字のみ）。
  ///
  /// DB保存・重複判定・各社へのスクレイピング送信は
  /// この正規化後の番号で行う（`6232-0148-6493` と `623201486493` を同一視するため）。
  static String normalize(String number) => number.replaceAll('-', '');

  /// 追跡番号の形式を検証する（10〜14桁の数字、ハイフン可）。
  static bool isValid(String number) {
    if (number.isEmpty) return false;
    final cleaned = normalize(number);
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) return false;
    return cleaned.length >= 10 && cleaned.length <= 14;
  }

  /// 追跡番号の桁数からキャリアを自動判別する。
  ///
  /// - 11桁または13桁: 日本郵便
  /// - 12桁: ヤマト運輸（佐川急便も12桁のため判別不可、手動選択が必要）
  ///
  /// 佐川急便の追跡番号はヤマト運輸と同じ12桁のケースが多く、
  /// 桁数のみでは両者を確実に区別できないため、12桁の場合はヤマト運輸を優先する。
  /// それ以外の桁数（10桁や14桁など）の場合は null を返す。
  ///
  /// 桁数だけでは確定できないため、実際にどのキャリアの荷物かは
  /// [carrierCandidates] の候補へ順に問い合わせて確定する（[TrackingRepository] 側）。
  ///
  /// 11〜13桁のみ「第一候補」を返す。10桁・14桁・9桁以下は単一推定できないため null。
  static Carrier? detectCarrier(String trackingNumber) {
    final cleaned = normalize(trackingNumber);
    if (cleaned.length == 11 ||
        cleaned.length == 12 ||
        cleaned.length == 13) {
      return carrierCandidates(cleaned).first;
    }
    return null;
  }

  /// 追跡番号の桁数から、該当しうるキャリアを優先順に列挙する。
  ///
  /// 各社の桁数仕様（2026年時点）:
  /// - ヤマト運輸: 11桁 / 12桁
  /// - 佐川急便: 10桁 / 12桁
  /// - 日本郵便: 11〜13桁（12桁はゆうパック等で一般的）
  ///
  /// 12桁は3社すべてが該当しうるため、桁数だけでは確定できない。
  /// 呼び出し側でこの候補順に各社へ問い合わせ、最初に取得できた会社を採用する。
  /// 該当桁数が無い場合（14桁など）は、取りこぼしを避けるため全社を候補にする。
  static List<Carrier> carrierCandidates(String trackingNumber) {
    final cleaned = normalize(trackingNumber);

    switch (cleaned.length) {
      case 10:
        // 佐川急便（加えて福山通運・西濃運輸も10桁だが本アプリは非対応）
        return const [Carrier.sagawa];
      case 11:
        // 日本郵便（書留等）とヤマト運輸が該当しうる
        return const [Carrier.japanPost, Carrier.yamato];
      case 12:
        // ヤマト・佐川・日本郵便のすべてが該当しうる。流通量の多い順に試す
        return const [Carrier.yamato, Carrier.sagawa, Carrier.japanPost];
      case 13:
        // 日本郵便（13桁の荷物系統）
        return const [Carrier.japanPost];
      default:
        // 10〜13桁以外（14桁など）は確定できないため全社を試す
        return const [Carrier.japanPost, Carrier.yamato, Carrier.sagawa];
    }
  }
}