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

  Color _avatarColor(Carrier carrier) {
    switch (carrier) {
      case Carrier.japanPost:
        return Colors.red.shade100;
      case Carrier.yamato:
        return Colors.orange.shade100;
      case Carrier.sagawa:
        return Colors.blue.shade100;
    }
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
    final carrier = info.carrier;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _avatarColor(carrier),
          child: Text(
            _carrierChar(carrier),
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          info.trackingNumber,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${info.currentStatus} · ${carrier.displayName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          info.lastUpdated != null
              ? _timeAgo(info.lastUpdated!)
              : (info.estimatedDelivery ?? ''),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(150),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
