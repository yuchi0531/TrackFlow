import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trackflow/domain/tracking_number.dart';
import 'package:trackflow/presentation/add_tracking/widgets/carrier_selector.dart';
import 'package:trackflow/provider/tracking_providers.dart';

class AddTrackingPage extends ConsumerStatefulWidget {
  const AddTrackingPage({super.key});

  @override
  ConsumerState<AddTrackingPage> createState() => _AddTrackingPageState();
}

class _AddTrackingPageState extends ConsumerState<AddTrackingPage> {
  final _numberController = TextEditingController();
  final _nicknameController = TextEditingController();
  String? _selectedCarrier;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // 追跡番号入力時にボタンの有効/無効を切り替える
    _numberController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _numberController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    // 改行・カンマ・スペース区切りで複数番号を受け付ける
    final numbers = splitTrackingNumbers(_numberController.text);
    if (numbers.isEmpty) return;

    // 配送会社は手動選択を必須にする。未選択の場合は選択を促す。
    final carrier = _selectedCarrier;
    if (carrier == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配送会社を選択してください')),
        );
      }
      return;
    }

    // 形式が正しい番号のみを対象にする（無効な番号はスキップ）
    final validNumbers =
        numbers.where(TrackingNumberValidator.isValid).toList();
    final invalidCount = numbers.length - validNumbers.length;
    if (validNumbers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('有効な追跡番号がありません（10〜14桁）')),
        );
      }
      return;
    }

    // 同一番号の重複追加を避けるため、順序を保ったまま重複を除去する
    final uniqueNumbers = validNumbers.toSet().toList();

    setState(() => _isSubmitting = true);

    try {
      final addTracking = ref.read(addTrackingProvider);
      final nickname = _nicknameController.text.trim().isEmpty
          ? null
          : _nicknameController.text.trim();

      // 各番号を順次登録する（fetch成功時のみ登録する既存ロジックを維持）
      var successCount = 0;
      final failures = <String>[];
      for (final number in uniqueNumbers) {
        try {
          await addTracking(
            trackingNumber: number,
            carrier: carrier,
            nickname: nickname,
          );
          successCount++;
        } catch (e) {
          failures.add(_friendlyErrorMessage(e));
        }
      }

      // 形式エラーでスキップした分も失敗として合算する
      if (invalidCount > 0) {
        failures.insert(0, '追跡番号の形式が正しくありません（10〜14桁）');
      }

      final summary = buildAddResultSummary(successCount, failures);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(summary)),
        );
        if (successCount > 0) {
          // 成功が1件以上なら一覧へ反映して戻る
          ref.invalidate(trackingListProvider);
          context.pop();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// 例外をユーザー向けのメッセージに変換
  static String _friendlyErrorMessage(Object e) {
    final msg = e.toString();
    if (msg.contains('既に登録されています')) {
      return 'この追跡番号は既に登録されています';
    }
    if (msg.contains('見つかりません') ||
        msg.contains('取得できません')) {
      return '指定された追跡番号の情報が見つかりませんでした';
    }
    if (msg.contains('SocketException') ||
        msg.contains('TimeoutException') ||
        msg.contains('networkFailure')) {
      return 'サーバーに接続できませんでした。時間をおいて再試行してください';
    }
    if (msg.contains('parseFailure')) {
      return '追跡ページの解析に失敗しました。時間をおいて再試行してください';
    }
    return 'エラーが発生しました。もう一度お試しください';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSubmit =
        _numberController.text.trim().isNotEmpty && !_isSubmitting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('追跡を追加'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _numberController,
              keyboardType: TextInputType.text,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '1234-5678-9012',
                labelText: '追跡番号',
                helperText: '複数ある場合は改行・カンマ・スペースで区切って入力',
              ),
            ),
            const SizedBox(height: 24),
            Text('配送会社', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            CarrierSelector(
              selectedCarrier: _selectedCarrier,
              onSelected: (carrier) {
                setState(() => _selectedCarrier = carrier);
              },
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                hintText: 'Amazonの注文',
                labelText: 'ニックネーム（任意）',
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canSubmit ? _submit : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('追跡を開始'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 追跡番号の入力文字列を改行・カンマ・スペース（全角含む）区切りで分割する。
/// 空文字は除外し、前後の空白を除去して返す。
List<String> splitTrackingNumbers(String input) {
  return input
      .split(RegExp(r'[\s,、]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// 成功/失敗件数と失敗の内訳（最初の1-2件）をまとめたメッセージを組み立てる。
String buildAddResultSummary(int successCount, List<String> failures) {
  if (failures.isEmpty) {
    return '$successCount件すべて登録しました';
  }
  final detail = failures.take(2).join('、');
  final more = failures.length > 2 ? ' ほか${failures.length - 2}件' : '';
  return '$successCount件成功、${failures.length}件失敗しました（$detail$more）';
}
