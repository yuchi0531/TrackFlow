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

  /// User-Agent（全社共通）
  static const userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';
}
