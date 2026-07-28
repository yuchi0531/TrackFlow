import 'package:flutter/material.dart';
import 'package:trackflow/domain/entities/carrier.dart';

class StatusHeader extends StatelessWidget {
  final String trackingNumber;
  final Carrier carrier;
  final String? itemType;
  final String currentStatus;

  const StatusHeader({
    super.key,
    required this.trackingNumber,
    required this.carrier,
    this.itemType,
    required this.currentStatus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(trackingNumber,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(carrier.displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
                if (itemType != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(itemType!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        )),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.circle,
                    size: 12,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(currentStatus,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      )),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
