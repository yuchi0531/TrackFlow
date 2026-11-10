import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/presentation/tracking_list/tracking_list_page.dart';
import 'package:trackflow/provider/tracking_providers.dart';

/// trackingListProvider を固定データで置き換えるための Notifier。
///
/// 削除は DB へ行かず state からの除去のみを行う（テスト用）。
class _FakeTrackingListNotifier extends TrackingListNotifier {
  final List<TrackingInfo> items;
  _FakeTrackingListNotifier(this.items);

  @override
  Future<List<TrackingInfo>> build() async => items;

  @override
  Future<void> delete({
    required String trackingNumber,
    required String carrier,
  }) async {
    final current = state.value ?? const <TrackingInfo>[];
    state = AsyncData(current
        .where((t) =>
            t.trackingNumber != trackingNumber || t.carrier.name != carrier)
        .toList());
  }
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
  group('セクション表示', () {
    testWidgets('配達中が終了済より上に表示される', (tester) async {
      final inTransit = _info('11111111111', '輸送中');
      final delivered = _info('22222222222', '配達完了');

      await tester.pumpWidget(_buildTestApp([inTransit, delivered]));
      await tester.pumpAndSettle();

      expect(find.text('配達中 (1)'), findsOneWidget);
      expect(find.text('終了済 (1)'), findsOneWidget);

      // 見出しの順序
      expect(
        tester.getTopLeft(find.text('配達中 (1)')).dy,
        lessThan(tester.getTopLeft(find.text('終了済 (1)')).dy),
      );
      // カード自体も配達中が上
      expect(
        tester.getTopLeft(find.text('11111111111')).dy,
        lessThan(tester.getTopLeft(find.text('22222222222')).dy),
      );
    });

    testWidgets('配達中のみのときは終了済の見出しが出ない', (tester) async {
      await tester.pumpWidget(_buildTestApp([
        _info('11111111111', '輸送中'),
        _info('33333333333', '情報を取得できませんでした'),
      ]));
      await tester.pumpAndSettle();

      // プレースホルダーも配達中側に含まれる
      expect(find.text('配達中 (2)'), findsOneWidget);
      expect(find.textContaining('終了済'), findsNothing);
    });

    testWidgets('全件配達完了なら配達中の見出しが出ない', (tester) async {
      await tester.pumpWidget(_buildTestApp([
        _info('22222222222', '配達完了'),
        _info('44444444444', 'お届け済み'),
      ]));
      await tester.pumpAndSettle();

      expect(find.textContaining('配達中'), findsNothing);
      expect(find.text('終了済 (2)'), findsOneWidget);
    });

    testWidgets('空リストでは EmptyState が表示される', (tester) async {
      await tester.pumpWidget(_buildTestApp([]));
      await tester.pumpAndSettle();

      expect(find.text('追跡中の荷物はありません'), findsOneWidget);
      expect(find.textContaining('配達中'), findsNothing);
    });
  });

  group('並び替え', () {
    final older =
        _info('11111111111', '輸送中', lastUpdated: DateTime(2026, 8, 1));
    final newer =
        _info('22222222222', '輸送中', lastUpdated: DateTime(2026, 8, 10));

    testWidgets('最終更新順を選ぶと同一セクション内で新しいものが先頭に来る', (tester) async {
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

  group('スワイプ削除', () {
    testWidgets('キャンセルすると削除されない', (tester) async {
      await tester.pumpWidget(_buildTestApp([
        _info('11111111111', '輸送中'),
        _info('22222222222', '配達完了'),
      ]));
      await tester.pumpAndSettle();

      await tester.drag(find.text('11111111111'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('追跡を削除'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(find.text('11111111111'), findsOneWidget);
      expect(find.text('配達中 (1)'), findsOneWidget);
    });

    testWidgets('削除すると一覧から消え、空になった見出しも消える', (tester) async {
      await tester.pumpWidget(_buildTestApp([
        _info('11111111111', '輸送中'),
        _info('22222222222', '配達完了'),
      ]));
      await tester.pumpAndSettle();

      await tester.drag(find.text('11111111111'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('追跡を削除'), findsOneWidget);
      // 背景ビューの「削除」と区別するためダイアログのボタンを指定する
      await tester.tap(find.widgetWithText(FilledButton, '削除'));
      await tester.pumpAndSettle();

      expect(find.text('11111111111'), findsNothing);
      // 配達中が0件になったので見出しごと消える
      expect(find.textContaining('配達中'), findsNothing);
      expect(find.text('終了済 (1)'), findsOneWidget);
    });
  });
}
