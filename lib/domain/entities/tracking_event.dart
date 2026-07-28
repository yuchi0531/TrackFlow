/// 個別の追跡イベント（配送履歴の1行）
class TrackingEvent {
  /// 生の日付文字列（"06/15 12:10" など）
  final String rawDate;

  /// パースされた日付（ベストエフォート）
  final DateTime? date;

  /// ステータス文字列（"引受", "持ち出し中" など）
  final String status;

  /// 担当店舗・営業所名
  final String? location;

  const TrackingEvent({
    required this.rawDate,
    this.date,
    required this.status,
    this.location,
  });

  Map<String, dynamic> toJson() => {
        'rawDate': rawDate,
        'date': date?.toIso8601String(),
        'status': status,
        'location': location,
      };
}
