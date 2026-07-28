import 'package:trackflow/domain/entities/tracking_info.dart';

/// トラッキングレポジトリの抽象インターフェース
abstract class TrackingRepository {
  /// 指定された追跡番号で配送状況を取得する
  /// ネットワーク経由でスクレイピングし、結果を返す
  Future<TrackingInfo> fetchTracking({
    required String trackingNumber,
    required String carrier,
  });

  /// 追跡番号が有効な形式か検証する
  bool isValidTrackingNumber(String number);
}
