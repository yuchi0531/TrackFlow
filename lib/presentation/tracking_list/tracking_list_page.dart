import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/domain/tracking_status.dart';
import 'package:trackflow/presentation/tracking_list/widgets/empty_state.dart';
import 'package:trackflow/presentation/tracking_list/widgets/tracking_card.dart';
import 'package:trackflow/provider/tracking_providers.dart';

/// 並び替えの選択肢
enum _SortBy { registration, lastUpdated }

class TrackingListPage extends ConsumerStatefulWidget {
  const TrackingListPage({super.key});

  @override
  ConsumerState<TrackingListPage> createState() => _TrackingListPageState();
}

class _TrackingListPageState extends ConsumerState<TrackingListPage> {
  _SortBy _sortBy = _SortBy.registration;

  /// 削除失敗時に Dismissible を作り直すための世代番号。
  ///
  /// dismiss 済みの Dismissible は同じ key のままツリーへ戻ると
  /// 「A dismissed Dismissible widget is still part of the tree」で落ちるため、
  /// 削除に失敗してアイテムを一覧へ復元する際はキーを変えて再生成する。
  int _dismissGeneration = 0;

  /// 並び替えを適用した新しいリストを返す。
  ///
  /// 登録順は Provider の並び（createdAt 降順）をそのまま使う。
  /// 並び替えはセクション（配達中／終了済）ごとに適用する。
  List<TrackingInfo> _sort(List<TrackingInfo> trackings) {
    switch (_sortBy) {
      case _SortBy.registration:
        return trackings;
      case _SortBy.lastUpdated:
        final sorted = [...trackings];
        sorted.sort((a, b) {
          final aUpdated = a.lastUpdated;
          final bUpdated = b.lastUpdated;
          if (aUpdated == null && bUpdated == null) return 0;
          if (aUpdated == null) return 1; // 履歴なし（null）は最後に
          if (bUpdated == null) return -1;
          return bUpdated.compareTo(aUpdated); // 新しい順
        });
        return sorted;
    }
  }

  Future<bool> _confirmDismiss(TrackingInfo info) async {
    final cs = Theme.of(context).colorScheme;
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
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
                child: const Text('削除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// スワイプ時にカードの下から現れる削除ビュー。
  ///
  /// カードと同じ角丸12でクリップし、カードの高さにそのまま収める
  /// （固定 height は指定せず Alignment.centerRight で縦中央に配置する）。
  Widget _buildDeleteBackground() {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: cs.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: cs.onError, size: 24),
            const SizedBox(width: 8),
            Text(
              '削除',
              style: TextStyle(
                color: cs.onError,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 見出しとカードをフラットなリストに積む
  /// （ListView.builder のインデックスと Dismissible の対応を保つため）。
  List<Widget> _buildEntries(List<TrackingInfo> trackings) {
    final inTransit = _sort(
      trackings.where((t) => !isDeliveredStatus(t.currentStatus)).toList(),
    );
    final finished = _sort(
      trackings.where((t) => isDeliveredStatus(t.currentStatus)).toList(),
    );

    final entries = <Widget>[];

    if (inTransit.isNotEmpty) {
      entries.add(_SectionHeader(
        key: const ValueKey('header_in_transit'),
        label: '配達中 (${inTransit.length})',
        color: Theme.of(context).colorScheme.primary,
      ));
      entries.addAll(inTransit.map(_buildCard));
    }

    if (finished.isNotEmpty) {
      entries.add(_SectionHeader(
        key: const ValueKey('header_finished'),
        label: '終了済 (${finished.length})',
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ));
      entries.addAll(finished.map(_buildCard));
    }

    return entries;
  }

  Widget _buildCard(TrackingInfo info) {
    final baseKey = '${info.trackingNumber}_${info.carrier.name}';
    return Padding(
      // セクション（配達中／終了済）をまたいで移動した際に、Dismissible が
      // 別アイテムの要素を再利用しないよう一意なキーを付ける。
      key: ValueKey('card_$baseKey'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        // 削除失敗時は世代番号を進めて、dismiss 済みの Dismissible を作り直す
        // （同じ key のままツリーへ戻すとアサーションで落ちるため）
        key: ValueKey('${baseKey}_$_dismissGeneration'),
        direction: DismissDirection.endToStart,
        dismissThresholds: const {DismissDirection.endToStart: 0.4},
        confirmDismiss: (_) => _confirmDismiss(info),
        onDismissed: (_) async {
          // 削除失敗時に SnackBar を出すため、await 前に取得しておく
          // （失敗時は state が復元され、この要素は破棄されうる）
          final messenger = ScaffoldMessenger.of(context);
          try {
            // NotifierのdeleteでDB削除前に state から即時除去するため、
            // 削除済みアイテムが一瞬戻る（Dismissibleアサーション）のを防ぐ。
            await ref.read(trackingListProvider.notifier).delete(
                  trackingNumber: info.trackingNumber,
                  carrier: info.carrier.name,
                );
          } catch (_) {
            // Notifier側で state は復元済み。dismiss 済みの Dismissible を
            // そのまま戻すとアサーションで落ちるため、キーを変えて作り直す。
            if (mounted) {
              setState(() => _dismissGeneration++);
            }
            messenger.showSnackBar(
              const SnackBar(
                content: Text('削除に失敗しました。通信状況を確認して再度お試しください'),
              ),
            );
          }
        },
        background: _buildDeleteBackground(),
        secondaryBackground: _buildDeleteBackground(),
        child: TrackingCard(
          info: info,
          onTap: () => context.push(
              '/detail/${info.trackingNumber}?carrier=${info.carrier.name}'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trackingsAsync = ref.watch(trackingListProvider);

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
      body: trackingsAsync.when(
        data: (trackings) {
          if (trackings.isEmpty) {
            // 空一覧でも pull-to-refresh できるよう RefreshIndicator で包む。
            // EmptyState はスクロール可能な領域の中央に置く。
            return RefreshIndicator(
              onRefresh: () async {
                // ignore: unused_result
                await ref.refresh(trackingListProvider.future);
              },
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: const EmptyState(),
                  ),
                ),
              ),
            );
          }
          final entries = _buildEntries(trackings);
          return RefreshIndicator(
            onRefresh: () async {
              // ref.refreshで確実に新しいFutureを取得して待機する
              // ignore: unused_result
              await ref.refresh(trackingListProvider.future);
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: entries.length,
              itemBuilder: (context, index) => entries[index],
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

/// セクション見出し（配達中／終了済）。件数を括弧で併記する。
class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;

  const _SectionHeader({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // カード間の 8px リズムを崩さないよう、下は詰める（カード側の余白と合算しない）
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
