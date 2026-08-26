import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:trackflow/presentation/add_tracking/add_tracking_page.dart';
import 'package:trackflow/provider/tracking_providers.dart';

void main() {
  group('splitTrackingNumbers', () {
    test('改行区切りで分割される', () {
      expect(
        splitTrackingNumbers('12345678901\n12345678902'),
        ['12345678901', '12345678902'],
      );
    });

    test('カンマ・スペース区切りで分割される', () {
      expect(
        splitTrackingNumbers('12345678901, 12345678902 12345678903'),
        ['12345678901', '12345678902', '12345678903'],
      );
    });

    test('全角カンマ区切りで分割される', () {
      expect(
        splitTrackingNumbers('12345678901、12345678902'),
        ['12345678901', '12345678902'],
      );
    });

    test('空白だけの要素は除外される', () {
      expect(splitTrackingNumbers('  12345678901  \n'), ['12345678901']);
    });

    test('空文字列は空リストを返す', () {
      expect(splitTrackingNumbers(''), isEmpty);
    });
  });

  group('buildAddResultSummary', () {
    test('全件成功のメッセージになる', () {
      expect(buildAddResultSummary(2, []), '2件すべて登録しました');
    });

    test('失敗がある場合は件数と内訳が表示される', () {
      expect(
        buildAddResultSummary(1, ['エラーA']),
        '1件成功、1件失敗しました（エラーA）',
      );
    });

    test('失敗が3件以上は最初の2件と残り件数が表示される', () {
      expect(
        buildAddResultSummary(0, ['エラーA', 'エラーB', 'エラーC']),
        '0件成功、3件失敗しました（エラーA、エラーB ほか1件）',
      );
    });
  });

  group('一括追加画面', () {
    GoRouter buildRouter(
      Future<void> Function({
        required String trackingNumber,
        required String carrier,
        String? nickname,
      }) addTracking,
    ) {
      return GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => context.push('/add'),
                  child: const Text('追加画面を開く'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/add',
            builder: (context, state) => const AddTrackingPage(),
          ),
        ],
      );
    }

    Future<void> openAddPage(WidgetTester tester) async {
      await tester.tap(find.text('追加画面を開く'));
      await tester.pumpAndSettle();
    }

    testWidgets('複数番号が順次登録され、成功時は一覧へ戻る', (tester) async {
      final added = <String>[];
      final router = buildRouter(
        ({
          required String trackingNumber,
          required String carrier,
          String? nickname,
        }) async {
          added.add(trackingNumber);
        },
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          addTrackingProvider.overrideWith((ref) {
            return ({
              required String trackingNumber,
              required String carrier,
              String? nickname,
            }) async {
              added.add(trackingNumber);
            };
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));

      await openAddPage(tester);

      // 3つの番号を改行区切りで入力（2つは有効、1つは9桁で無効）
      await tester.enterText(
        find.byType(TextField).first,
        '12345678901\n12345678902\n123456789',
      );
      await tester.pump();
      await tester.tap(find.text('ヤマト運輸'));
      await tester.pump();
      await tester.tap(find.text('追跡を開始'));
      await tester.pumpAndSettle();

      // 有効な番号のみ登録され、画面は一覧(ルート)へ戻る
      expect(added, ['12345678901', '12345678902']);
      expect(find.text('追加画面を開く'), findsOneWidget);
      // 無効な1件が失敗として集計されたサマリーが表示される
      expect(
        find.textContaining('2件成功、1件失敗しました'),
        findsOneWidget,
      );
      expect(
        find.textContaining('追跡番号の形式が正しくありません（10〜14桁）'),
        findsOneWidget,
      );
    });

    testWidgets('全件失敗の場合は画面に留まり失敗の内訳が表示される', (tester) async {
      final router = buildRouter(
        ({
          required String trackingNumber,
          required String carrier,
          String? nickname,
        }) async {
          throw Exception('取得できません');
        },
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          addTrackingProvider.overrideWith((ref) {
            return ({
              required String trackingNumber,
              required String carrier,
              String? nickname,
            }) async {
              throw Exception('取得できません');
            };
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));

      await openAddPage(tester);

      await tester.enterText(
        find.byType(TextField).first,
        '12345678901\n12345678902',
      );
      await tester.pump();
      await tester.tap(find.text('ヤマト運輸'));
      await tester.pump();
      await tester.tap(find.text('追跡を開始'));
      await tester.pumpAndSettle();

      // 成功0件のため一覧へ戻らず、追加画面のまま
      expect(find.text('追跡を追加'), findsOneWidget);
      expect(find.text('追加画面を開く'), findsNothing);
      // 失敗件数と内訳（最初の1-2件）がSnackBarに表示される
      expect(
        find.textContaining('0件成功、2件失敗しました'),
        findsOneWidget,
      );
      // 失敗の内訳（最初の1-2件）がSnackBarに表示される
      expect(
        find.textContaining('指定された追跡番号の情報が見つかりませんでした'),
        findsOneWidget,
      );
    });
  });
}