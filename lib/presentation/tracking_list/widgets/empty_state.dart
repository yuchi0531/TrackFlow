import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

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
              Icons.inventory_2_outlined,
              size: 80,
              color: theme.colorScheme.onSurface.withAlpha(100),
            ),
            const SizedBox(height: 16),
            Text(
              '追跡中の荷物はありません',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(180),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '+ ボタンから追跡番号を追加してください',
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
