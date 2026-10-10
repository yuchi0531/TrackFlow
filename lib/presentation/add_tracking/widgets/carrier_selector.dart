import 'package:flutter/material.dart';

/// 配送会社セレクターで「自動判定」を表す値。
///
/// [selectedCarrier] がこの値のとき、登録時に桁数から候補を絞って
/// 各社へ実際に問い合わせ、会社を自動判定する。
const String kAutoDetectCarrier = 'auto';

class CarrierSelector extends StatelessWidget {
  final String? selectedCarrier;
  final ValueChanged<String?> onSelected;

  const CarrierSelector({super.key, this.selectedCarrier, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final options = [
      (kAutoDetectCarrier, '自動判定', Icons.auto_awesome),
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
