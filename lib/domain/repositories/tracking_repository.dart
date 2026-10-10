import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/domain/tracking_number.dart';

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

  /// 追跡番号から配送会社を自動判定し、追跡情報を取得する。
  ///
  /// 桁数から候補を絞り、各社へ順に問い合わせて最初に取得できた会社と
  /// 追跡情報を返す。どの会社でも取得できない場合は null を返す。
  Future<({Carrier carrier, TrackingInfo info})?> detectCarrierAndFetch(
    String trackingNumber,
  ) async {
    for (final carrier in carrierCandidates(trackingNumber)) {
      try {
        final info = await fetchTracking(
          trackingNumber: trackingNumber,
          carrier: carrier.name,
        );
        return (carrier: carrier, info: info);
      } on Exception {
        // 次の候補を試す
        continue;
      }
    }
    return null;
  }

  /// 桁数から該当しうる配送会社を優先順に列挙する（既定実装）。
  List<Carrier> carrierCandidates(String trackingNumber) =>
      TrackingNumberValidator.carrierCandidates(trackingNumber);
}
