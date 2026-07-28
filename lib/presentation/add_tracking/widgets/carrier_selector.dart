import 'package:flutter/material.dart';

class CarrierSelector extends StatelessWidget {
  final String? selectedCarrier;
  final ValueChanged<String?> onSelected;

  const CarrierSelector({super.key, this.selectedCarrier, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final options = [
      (null, '自動判別', Icons.auto_awesome),
      ('japanPost', '日本郵便', Icons.mail_outline),
      ('yamato', 'ヤマト運輸', Icons.local_shipping_outlined),
      ('sagawa', '佐川急便', Icons.inventory_2_outlined),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: options.map((opt) {
        final selected = selectedCarrier == opt.$1;
        return FilterChip(
          label: Text(opt.$2),
          selected: selected,
          onSelected: (_) => onSelected(opt.$1),
          avatar: Icon(opt.$3, size: 18),
        );
      }).toList(),
    );
  }
}
