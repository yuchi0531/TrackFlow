import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/presentation/tracking_list/tracking_list_page.dart';
import 'package:trackflow/provider/tracking_providers.dart';

/// trackingListProvider を固定データで置き換えるための Notifier。
class _FakeTrackingListNotifier extends TrackingListNotifier {
  final List<TrackingInfo> items;
  _FakeTrackingListNotifier(this.items);

  @override
  Future<List<TrackingInfo>> build() async => items;
}

TrackingInfo _info(String number, String status, {DateTime? lastUpdated}) {
  return TrackingInfo(
    trackingNumber: number,
    carrier: Carrier.yamato,
    currentStatus: status,
    events: const [],
    lastUpdated: lastUpdated,
  );
}

Widget _buildTestApp(List<TrackingInfo> items) {
  return ProviderScope(
    overrides: [
      trackingListProvider.overrideWith(() => _FakeTrackingListNotifier(items)),
    ],
    child: const MaterialApp(home: TrackingListPage()),
  );
}

void main() {
  group('一覧の絞り込み', () {
    final inTransit = _info('11111111111', '輸送中');
    final delivered = _info('22222222222', '配達完了');

    testWidgets('デフォルト（すべて）では全ての追跡が表示される', (tester) async {
      await tester.pumpWidget(_buildTestApp([inTransit, delivered]));
      await tester.pumpAndSettle();

      expect(find.text('11111111111'), findsOneWidget);
      expect(find.text('22222222222'), findsOneWidget);
    });

    testWidgets('「配達中」フィルタで配達中のみ表示される', (tester) async {
      await tester.pumpWidget(_buildTestApp([inTransit, delivered]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('配達中'));
      await tester.pumpAndSettle();

      expect(find.text('11111111111'), findsOneWidget);
      expect(find.text('22222222222'), findsNothing);
    });

    testWidgets('「配達済み」フィルタで配達済みのみ表示される', (tester) async {
      await tester.pumpWidget(_buildTestApp([inTransit, delivered]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('配達済み'));
      await tester.pumpAndSettle();

      expect(find.text('11111111111'), findsNothing);
      expect(find.text('22222222222'), findsOneWidget);
    });

    testWidgets('フィルタで0件になった場合は空メッセージが表示される', (tester) async {
      await tester.pumpWidget(_buildTestApp([inTransit]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('配達済み'));
      await tester.pumpAndSettle();

      expect(find.text('該当する追跡がありません'), findsOneWidget);
    });
  });

  group('配達完了の自動アーカイブ', () {
    final inTransit = _info('11111111111', '輸送中');
    final delivered = _info('22222222222', '配達完了');

    testWidgets('トグルONで配達完了が一覧から隠れる', (tester) async {
      await tester.pumpWidget(_buildTestApp([inTransit, delivered]));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('22222222222'), findsNothing);
      expect(find.text('11111111111'), findsOneWidget);
    });

    testWidgets('トグルONでも「配達済み」フィルタ中は配達完了が表示される', (tester) async {
      await tester.pumpWidget(_buildTestApp([inTransit, delivered]));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      await tester.tap(find.text('配達済み'));
      await tester.pumpAndSettle();

      expect(find.text('22222222222'), findsOneWidget);
    });
  });

  group('並び替え', () {
    final older =
        _info('11111111111', '輸送中', lastUpdated: DateTime(2026, 8, 1));
    final newer =
        _info('22222222222', '輸送中', lastUpdated: DateTime(2026, 8, 10));

    testWidgets('最終更新順を選ぶと新しいものが先頭に来る', (tester) async {
      await tester.pumpWidget(_buildTestApp([older, newer]));
      await tester.pumpAndSettle();

      // デフォルトは登録順（Providerの並び = older が先頭）
      expect(
        tester.getTopLeft(find.text('11111111111')).dy,
        lessThan(tester.getTopLeft(find.text('22222222222')).dy),
      );

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最終更新順'));
      await tester.pumpAndSettle();

      // 最終更新順（新しい newer が先頭）
      expect(
        tester.getTopLeft(find.text('22222222222')).dy,
        lessThan(tester.getTopLeft(find.text('11111111111')).dy),
      );
    });
  });
}