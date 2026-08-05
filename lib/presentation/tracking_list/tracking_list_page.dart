import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/presentation/tracking_list/widgets/empty_state.dart';
import 'package:trackflow/presentation/tracking_list/widgets/tracking_card.dart';
import 'package:trackflow/provider/tracking_providers.dart';

class TrackingListPage extends ConsumerWidget {
  const TrackingListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingsAsync = ref.watch(trackingListProvider);
    final theme = Theme.of(context);

    Future<bool> confirmDismiss(TrackingInfo info) async {
      return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('追跡を削除'),
              content: Text('${info.trackingNumber}\nこの追跡を削除しますか？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('削除'),
                ),
              ],
            ),
          ) ??
          false;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('TrackFlow'),
      ),
      body: trackingsAsync.when(
        data: (trackings) {
          if (trackings.isEmpty) {
            return const EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async {
              // ref.refreshで確実に新しいFutureを取得して待機する
              // ignore: unused_result
              await ref.refresh(trackingListProvider.future);
            },
            child: ListView.builder(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: trackings.length,
              itemBuilder: (context, index) {
                final info = trackings[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Dismissible(
                    key: ValueKey(
                        '${info.trackingNumber}_${info.carrier.name}'),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => confirmDismiss(info),
                    onDismissed: (_) async {
                      try {
                        final deleteFn = ref.read(deleteTrackingProvider);
                        await deleteFn(
                          trackingNumber: info.trackingNumber,
                          carrier: info.carrier.name,
                        );
                      } catch (e) {
                        // 削除に失敗した場合、リストを再描画して復元
                        debugPrint('Failed to delete tracking: $e');
                      } finally {
                        ref.invalidate(trackingListProvider);
                      }
                    },
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.delete_outline,
                          color: theme.colorScheme.onError, size: 28),
                    ),
                    child: TrackingCard(
                      info: info,
                      onTap: () => context.push(
                          '/detail/${info.trackingNumber}?carrier=${info.carrier.name}'),
                    ),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text('データの読み込みに失敗しました',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(trackingListProvider),
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/add'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
