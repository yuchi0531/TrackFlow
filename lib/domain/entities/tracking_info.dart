import 'carrier.dart';
import 'tracking_event.dart';

/// 追跡結果の完全な情報
class TrackingInfo {
  /// 追跡番号
  final String trackingNumber;

  /// 配送会社
  final Carrier carrier;

  /// 商品種別（日本郵便・ヤマトのみ）
  final String? itemType;

  /// 最新ステータス
  final String currentStatus;

  /// 配達予定日時（ヤマト・佐川のみ）
  final String? estimatedDelivery;

  /// 追跡イベント履歴（時系列順、古い順）
  final List<TrackingEvent> events;

  /// 最後に更新した日時
  final DateTime? lastUpdated;

  const TrackingInfo({
    required this.trackingNumber,
    required this.carrier,
    this.itemType,
    required this.currentStatus,
    this.estimatedDelivery,
    required this.events,
    this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
        'trackingNumber': trackingNumber,
        'carrier': carrier.name,
        'itemType': itemType,
        'currentStatus': currentStatus,
        'estimatedDelivery': estimatedDelivery,
        'events': events.map((e) => e.toJson()).toList(),
        'lastUpdated': lastUpdated?.toIso8601String(),
      };
}
