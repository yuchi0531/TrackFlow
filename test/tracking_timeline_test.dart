import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackflow/domain/entities/tracking_event.dart';
import 'package:trackflow/presentation/detail/widgets/tracking_timeline.dart';

/// [TrackingTimeline] をテスト用の最小構成で描画する。
Widget _wrap(List<TrackingEvent> events) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: TrackingTimeline(events: events),
      ),
    ),
  );
}

void main() {
  group('TrackingTimeline', () {
    // events の契約は「古い順」なので、先頭が最古・末尾が最新。
    final events = [
      const TrackingEvent(rawDate: '06/15 10:00', status: '引受', location: '東京'),
      const TrackingEvent(rawDate: '06/16 09:00', status: '輸送中', location: '大阪'),
      const TrackingEvent(
          rawDate: '06/17 15:30', status: '配達完了', location: '福岡'),
    ];

    testWidgets('新しい順（最新が先頭）に描画される', (tester) async {
      await tester.pumpWidget(_wrap(events));

      // 3件とも描画されている
      expect(find.text('引受'), findsOneWidget);
      expect(find.text('輸送中'), findsOneWidget);
      expect(find.text('配達完了'), findsOneWidget);

      // 上から 配達完了 → 輸送中 → 引受 の順
      final latestY = tester.getTopLeft(find.text('配達完了')).dy;
      final middleY = tester.getTopLeft(find.text('輸送中')).dy;
      final oldestY = tester.getTopLeft(find.text('引受')).dy;

      expect(latestY, lessThan(middleY), reason: '最新イベントが最上部');
      expect(middleY, lessThan(oldestY), reason: '古いイベントほど下');
    });

    testWidgets('先頭（最新）のイベントだけが強調される', (tester) async {
      await tester.pumpWidget(_wrap(events));

      final theme = Theme.of(tester.element(find.text('配達完了')));
      final latestStyle = tester.widget<Text>(find.text('配達完了')).style;
      final olderStyle = tester.widget<Text>(find.text('輸送中')).style;

      expect(latestStyle?.fontWeight, FontWeight.bold);
      expect(latestStyle?.color, theme.colorScheme.primary);
      expect(olderStyle?.fontWeight, FontWeight.normal);
      expect(olderStyle?.color, theme.colorScheme.onSurface);
    });

    testWidgets('先頭のステータスが events.last と一致する', (tester) async {
      await tester.pumpWidget(_wrap(events));

      // 一覧の先頭に描画されているテキストが events.last.status であること
      final statusTexts = ['配達完了', '輸送中', '引受'];
      final ys = {
        for (final s in statusTexts) s: tester.getTopLeft(find.text(s)).dy,
      };
      final topmost =
          ys.entries.reduce((a, b) => a.value <= b.value ? a : b).key;

      expect(topmost, events.last.status);
    });

    testWidgets('1件でもクラッシュしない', (tester) async {
      await tester.pumpWidget(_wrap([events.last]));

      expect(tester.takeException(), isNull);
      expect(find.text('配達完了'), findsOneWidget);
    });

    testWidgets('0件でもクラッシュしない', (tester) async {
      await tester.pumpWidget(_wrap(const []));

      expect(tester.takeException(), isNull);
      expect(find.byType(TrackingTimeline), findsOneWidget);
    });
  });
}
