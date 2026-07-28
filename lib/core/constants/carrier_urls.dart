/// 各配送会社の追跡用エンドポイント定数
class CarrierUrls {
  CarrierUrls._();

  /// 日本郵便 追跡URL（スクレイピング用）
  static const japanPostTrackingUrl =
      'https://trackings.post.japanpost.jp/services/srv/search/direct';

  /// ヤマト運輸 追跡URL（スクレイピング用）
  static const yamatoTrackingUrl =
      'https://toi.kuronekoyamato.co.jp/cgi-bin/tneko';

  /// 佐川急便 追跡URL（スクレイピング用）
  static const sagawaTrackingUrl =
      'https://k2k.sagawa-exp.co.jp/p/web/okurijosearch.do';

  /// 日本郵便 公開追跡URL（番号付き）
  static String japanPostPublicUrl(String number) =>
      'https://trackings.post.japanpost.jp/services/srv/search/direct?reqCodeNo1=$number&locale=ja';

  /// ヤマト運輸 公開追跡URL（番号付き）
  static String yamatoPublicUrl(String number) =>
      'https://toi.kuronekoyamato.co.jp/cgi-bin/tneko?number01=$number';

  /// 佐川急便 公開追跡URL（番号付き）
  static String sagawaPublicUrl(String number) =>
      'https://k2k.sagawa-exp.co.jp/p/web/okurijosearch.do?okurijoNo=$number';

  /// User-Agent（全社共通）
  static const userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';
}
