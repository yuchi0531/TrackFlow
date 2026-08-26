import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/presentation/tracking_list/widgets/empty_state.dart';
import 'package:trackflow/presentation/tracking_list/widgets/tracking_card.dart';
import 'package:trackflow/provider/background_provider.dart';
import 'package:trackflow/provider/tracking_providers.dart';

/// ステータス絞り込みの選択肢
enum _StatusFilter { all, inTransit, delivered }

/// 並び替えの選択肢
enum _SortBy { registration, lastUpdated }

class TrackingListPage extends ConsumerStatefulWidget {
  const TrackingListPage({super.key});

  @override
  ConsumerState<TrackingListPage> createState() => _TrackingListPageState();
}

class _TrackingListPageState extends ConsumerState<TrackingListPage> {
  _StatusFilter _filterStatus = _StatusFilter.all;
  _SortBy _sortBy = _SortBy.registration;

  /// 配達完了の自動アーカイブ（ON で配達済みカードを一覧から隠す）
  bool _hideDelivered = false;

  /// `trackingListProvider` のデータに絞り込み・並び替え・自動アーカイブを適用する。
  /// Provider側は変更せず、UI側のローカル状態で表示を制御する。
  List<TrackingInfo> _applyFilterAndSort(List<TrackingInfo> trackings) {
    var result = trackings;

    // ステータス絞り込み
    switch (_filterStatus) {
      case _StatusFilter.all:
        break;
      case _StatusFilter.inTransit:
        result =
            result.where((t) => !isDeliveredStatus(t.currentStatus)).toList();
      case _StatusFilter.delivered:
        result = result.where((t) => isDeliveredStatus(t.currentStatus)).toList();
    }

    // 配達完了の自動アーカイブ。
    // 「配達済み」フィルタ選択中はユーザーが明示的に見たい場合なので、
    // トグルがONでも表示する。
    if (_hideDelivered && _filterStatus != _StatusFilter.delivered) {
      result =
          result.where((t) => !isDeliveredStatus(t.currentStatus)).toList();
    }

    // 並び替え
    switch (_sortBy) {
      case _SortBy.registration:
        // 登録順（Providerの並び = createdAt 降順）をそのまま使う
        break;
      case _SortBy.lastUpdated:
        final sorted = [...result];
        sorted.sort((a, b) {
          final aUpdated = a.lastUpdated;
          final bUpdated = b.lastUpdated;
          if (aUpdated == null && bUpdated == null) return 0;
          if (aUpdated == null) return 1; // 履歴なし（null）は最後に
          if (bUpdated == null) return -1;
          return bUpdated.compareTo(aUpdated); // 新しい順
        });
        result = sorted;
    }

    return result;
  }

  Future<bool> _confirmDismiss(TrackingInfo info) async {
    final theme = Theme.of(context);
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

  @override
  Widget build(BuildContext context) {
    final trackingsAsync = ref.watch(trackingListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TrackFlow'),
        actions: [
          PopupMenuButton<_SortBy>(
            icon: const Icon(Icons.sort),
            tooltip: '並び替え',
            initialValue: _sortBy,
            onSelected: (value) => setState(() => _sortBy = value),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _SortBy.registration,
                child: Text('登録順'),
              ),
              PopupMenuItem(
                value: _SortBy.lastUpdated,
                child: Text('最終更新順'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<_StatusFilter>(
              segments: const [
                ButtonSegment(
                  value: _StatusFilter.all,
                  label: Text('すべて'),
                ),
                ButtonSegment(
                  value: _StatusFilter.inTransit,
                  label: Text('配達中'),
                ),
                ButtonSegment(
                  value: _StatusFilter.delivered,
                  label: Text('配達済み'),
                ),
              ],
              selected: {_filterStatus},
              onSelectionChanged: (selection) =>
                  setState(() => _filterStatus = selection.first),
              showSelectedIcon: false,
            ),
          ),
          SwitchListTile(
            title: const Text('配達完了を表示しない'),
            subtitle: const Text('配達済みの荷物を一覧から隠します'),
            value: _hideDelivered,
            onChanged: (value) => setState(() => _hideDelivered = value),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          Expanded(
            child: trackingsAsync.when(
              data: (trackings) {
                if (trackings.isEmpty) {
                  return const EmptyState();
                }
                final visible = _applyFilterAndSort(trackings);
                if (visible.isEmpty) {
                  // 絞り込みで0件になった場合の空メッセージ（EmptyStateは流用しない）
                  return const _NoMatchState();
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    // ref.refreshで確実に新しいFutureを取得して待機する
                    // ignore: unused_result
                    await ref.refresh(trackingListProvider.future);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final info = visible[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Dismissible(
                          key: ValueKey(
                              '${info.trackingNumber}_${info.carrier.name}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) => _confirmDismiss(info),
                          onDismissed: (_) async {
                            // NotifierのdeleteでDB削除前に state から即時除去するため、
                            // 削除済みアイテムが一瞬戻る（Dismissibleアサーション）のを防ぐ。
                            await ref
                                .read(trackingListProvider.notifier)
                                .delete(
                                  trackingNumber: info.trackingNumber,
                                  carrier: info.carrier.name,
                                );
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
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.grey),
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/add'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 絞り込み結果が0件のときに表示するシンプルな空メッセージ
class _NoMatchState extends StatelessWidget {
  const _NoMatchState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withAlpha(100),
            ),
            const SizedBox(height: 12),
            Text(
              '該当する追跡がありません',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(180),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '絞り込み条件を変更してください',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(120),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
