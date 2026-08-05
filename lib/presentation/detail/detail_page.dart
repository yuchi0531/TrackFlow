import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trackflow/presentation/detail/widgets/delivery_estimate.dart';
import 'package:trackflow/presentation/detail/widgets/status_header.dart';
import 'package:trackflow/presentation/detail/widgets/tracking_timeline.dart';
import 'package:trackflow/provider/tracking_providers.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingAsync = ref.watch(trackingDetailProvider(
      (number: trackingNumber, carrier: carrier),
    ));

    return Scaffold(
      appBar: AppBar(
        title: const Text('追跡詳細'),
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
