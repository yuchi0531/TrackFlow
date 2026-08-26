import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:trackflow/core/constants/carrier_urls.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/presentation/detail/widgets/delivery_estimate.dart';
import 'package:trackflow/presentation/detail/widgets/status_header.dart';
import 'package:trackflow/presentation/detail/widgets/tracking_timeline.dart';
import 'package:trackflow/provider/tracking_providers.dart';
import 'package:url_launcher/url_launcher.dart';

class DetailPage extends ConsumerWidget {
  final String trackingNumber;
  final String carrier;

  const DetailPage({
    super.key,
    required this.trackingNumber,
    this.carrier = 'japanPost',
  });

  /// 例外メッセージをユーザーフレンドリーな表現に変換
  static String _friendlyErrorMessage(String raw) {
    if (raw.contains('SocketException') || raw.contains('TimeoutException')) {
      return 'ネットワークに接続できません。電波状況を確認してください。';
    }
    if (raw.contains('networkFailure')) {
      return 'サーバーに接続できませんでした。時間をおいて再試行してください。';
    }
    if (raw.contains('notFound') || raw.contains('見つかりません')) {
      return '指定された追跡番号の情報が見つかりませんでした。';
    }
    if (raw.contains('parseFailure')) {
      return '追跡ページの解析に失敗しました。時間をおいて再試行してください。';
    }
    return 'エラーが発生しました。再試行してください。';
  }

  /// 公式追跡ページをブラウザで開く（番号を埋め込めるキャリアは埋め込む）
  Future<void> _openOfficialSite(BuildContext context) async {
    final carrier = Carrier.fromString(this.carrier);
    final String url;
    switch (carrier) {
      case Carrier.japanPost:
        url = CarrierUrls.japanPostWebTrackingUrl(trackingNumber);
      case Carrier.yamato:
        url = CarrierUrls.yamatoWebTrackingUrl;
      case Carrier.sagawa:
        url = CarrierUrls.sagawaWebTrackingUrl;
    }

    final opened =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ブラウザを開けませんでした')),
      );
    }
  }

  /// 追跡番号をクリップボードにコピー
  Future<void> _copyTrackingNumber(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: trackingNumber));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('追跡番号をコピーしました')),
      );
    }
  }

  /// 追跡番号を共有
  Future<void> _shareTrackingNumber(BuildContext context) async {
    await SharePlus.instance.share(
      ShareParams(text: trackingNumber, subject: '荷物追跡番号'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingAsync = ref.watch(trackingDetailProvider(
      (number: trackingNumber, carrier: carrier),
    ));

    return Scaffold(
      appBar: AppBar(
        title: const Text('追跡詳細'),
        actions: [
          IconButton(
            tooltip: '公式サイトで確認',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openOfficialSite(context),
          ),
          IconButton(
            tooltip: '追跡番号をコピー',
            icon: const Icon(Icons.copy),
            onPressed: () => _copyTrackingNumber(context),
          ),
          IconButton(
            tooltip: '追跡番号を共有',
            icon: const Icon(Icons.share),
            onPressed: () => _shareTrackingNumber(context),
          ),
        ],
      ),
      body: trackingAsync.when(
        data: (data) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            StatusHeader(
              trackingNumber: data.trackingNumber,
              carrier: data.carrier,
              itemType: data.itemType,
              currentStatus: data.currentStatus,
            ),
            if (data.estimatedDelivery != null) ...[
              const SizedBox(height: 12),
              DeliveryEstimateCard(
                estimatedDelivery: data.estimatedDelivery!,
              ),
            ],
            const SizedBox(height: 16),
            TrackingTimeline(events: data.events),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text('追跡情報の取得に失敗しました',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 4),
              Text(_friendlyErrorMessage(error.toString()),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(
                    trackingDetailProvider(
                        (number: trackingNumber, carrier: carrier))),
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
