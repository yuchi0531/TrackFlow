import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trackflow/presentation/tracking_list/widgets/empty_state.dart';
import 'package:trackflow/presentation/tracking_list/widgets/tracking_card.dart';
import 'package:trackflow/provider/tracking_providers.dart';

class TrackingListPage extends ConsumerWidget {
  const TrackingListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingsAsync = ref.watch(trackingListProvider);

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
              ref.invalidate(trackingListProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: trackings.length,
              itemBuilder: (context, index) {
                final info = trackings[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TrackingCard(
                    info: info,
                    onTap: () => context.push(
                        '/detail/${info.trackingNumber}?carrier=${info.carrier.name}'),
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
