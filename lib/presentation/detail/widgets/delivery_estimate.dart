import 'package:flutter/material.dart';

class DeliveryEstimateCard extends StatelessWidget {
  final String estimatedDelivery;
  const DeliveryEstimateCard({super.key, required this.estimatedDelivery});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.schedule, color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('配達予定日',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withAlpha(179),
                    )),
                const SizedBox(height: 4),
                Text(estimatedDelivery,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
