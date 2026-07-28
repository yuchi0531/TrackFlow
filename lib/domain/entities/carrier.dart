/// 配送会社の種類
enum Carrier {
  /// ヤマト運輸
  yamato('ヤマト運輸', 'Yamato Transport'),

  /// 佐川急便
  sagawa('佐川急便', 'Sagawa Express'),

  /// 日本郵便
  japanPost('日本郵便', 'Japan Post');

  /// 日本語表示名
  final String displayName;

  /// 英語表示名
  final String englishName;

  const Carrier(this.displayName, this.englishName);

  /// 文字列からCarrierに変換
  static Carrier fromString(String value) {
    return Carrier.values.firstWhere(
      (c) => c.name == value,
      orElse: () => Carrier.yamato,
    );
  }
}
