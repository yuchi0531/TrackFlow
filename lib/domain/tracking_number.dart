import 'package:trackflow/domain/entities/carrier.dart';

/// 追跡番号の検証とキャリア自動判別を行うドメイン層ユーティリティ。
///
/// Presentation 層から Repository の実装クラスに依存しないよう、
/// 純粋な静的処理を domain 層へ分離した。
class TrackingNumberValidator {
  /// 追跡番号の形式を検証する（10〜14桁の数字、ハイフン可）。
  static bool isValid(String number) {
    if (number.isEmpty) return false;
    final cleaned = number.replaceAll('-', '');
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
  static Carrier? detectCarrier(String trackingNumber) {
    final cleaned = trackingNumber.replaceAll('-', '');

    if (cleaned.length == 11 || cleaned.length == 13) {
      return Carrier.japanPost;
    }
    if (cleaned.length == 12) {
      return Carrier.yamato;
    }
    return null;
  }
}