import 'package:flutter/material.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';

class TrackingCard extends StatelessWidget {
  final TrackingInfo info;
  final VoidCallback onTap;

  const TrackingCard({
    super.key,
    required this.info,
    required this.onTap,
  });

  /// 配送状況に応じたインジケーター色
  Color _statusColor(String status) {
    final s = status;
    if (s.contains('配達完了') || s.contains('お届け済み') || s.contains('投函完了')) {
      return Colors.green;
    }
    if (s.contains('持ち出し中') || s.contains('配達中') || s.contains('輸送中')) {
      return Colors.blue;
    }
    if (s.contains('引受') || s.contains('発送') || s.contains('通過')) {
      return Colors.orange;
    }
    if (s.contains('持戻') || s.contains('返送') || s.contains('エラー') || s.contains('見つかりません')) {
      return Colors.red;
    }
    return Colors.grey;
  }

  /// 配送状況に応じたアイコン
  IconData _statusIcon(String status) {
    final s = status;
    if (s.contains('配達完了') || s.contains('お届け済み') || s.contains('投函完了')) {
      return Icons.check_circle;
    }
    if (s.contains('持ち出し中') || s.contains('配達中')) {
      return Icons.local_shipping;
    }
    if (s.contains('輸送中') || s.contains('通過')) {
      return Icons.flight;
    }
    if (s.contains('引受') || s.contains('発送')) {
      return Icons.inventory_2;
    }
    if (s.contains('持戻') || s.contains('返送')) {
      return Icons.replay;
    }
    if (s.contains('エラー') || s.contains('見つかりません')) {
      return Icons.error_outline;
    }
    return Icons.circle;
  }

  String _carrierChar(Carrier carrier) {
    switch (carrier) {
      case Carrier.japanPost:
        return '郵';
      case Carrier.yamato:
        return 'ヤ';
      case Carrier.sagawa:
        return '佐';
    }
  }

  Color _carrierColor(Carrier carrier) {
    switch (carrier) {
      case Carrier.japanPost:
        return Colors.red.shade700;
      case Carrier.yamato:
        return Colors.orange.shade700;
      case Carrier.sagawa:
        return Colors.blue.shade700;
    }
  }

  String _timeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return 'たった今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    if (diff.inDays < 7) return '${diff.inDays}日前';
    return '${diff.inDays ~/ 7}週間前';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(info.currentStatus);
    final statusIcon = _statusIcon(info.currentStatus);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: statusColor.withAlpha(120),
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 16, 14),
          child: Row(
            children: [
              // 左端の色付きアクセントバー
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // ステータスインジケーター（アイコン）
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  statusIcon,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              // 本文
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            info.trackingNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 配送会社タグ
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _carrierColor(info.carrier).withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _carrierChar(info.carrier),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _carrierColor(info.carrier),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          info.currentStatus,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          info.carrier.displayName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 最終更新時間
              if (info.lastUpdated != null)
                Text(
                  _timeAgo(info.lastUpdated!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
