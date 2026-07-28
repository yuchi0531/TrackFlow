import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';

import 'japan_post_tracker.dart';
import 'yamato_tracker.dart';
import 'sagawa_tracker.dart';

/// トラッキング例外
class TrackerException implements Exception {
  final TrackerErrorType type;
  final String message;
  final int? statusCode;

  const TrackerException({
    required this.type,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'TrackerException($type): $message';
}

/// エラー種別
enum TrackerErrorType {
  networkFailure,
  notFound,
  parseFailure,
  invalidTrackingNumber,
}

/// トラッカー共通インターフェース
abstract class CarrierTracker {
  /// 配送会社ID
  String get carrierId;

  /// 追跡番号で追跡を実行する（HTTPリクエストを含む）
  Future<TrackingInfo> fetch(String trackingNumber);

  /// HTML文字列から追跡情報をパースする
  TrackingInfo parse(String html, String trackingNumber);
}

/// トラッカーファクトリー
class TrackerFactory {
  TrackerFactory._();

  /// Carrier enum からトラッカーを生成
  static CarrierTracker create(Carrier carrier) {
    switch (carrier) {
      case Carrier.japanPost:
        return JapanPostTracker();
      case Carrier.yamato:
        return YamatoTracker();
      case Carrier.sagawa:
        return SagawaTracker();
    }
  }
}
