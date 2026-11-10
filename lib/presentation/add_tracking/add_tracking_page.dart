import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trackflow/domain/tracking_url.dart';
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

  /// 既定は「自動判定」。明示的に会社を選ぶこともできる。
  String? _selectedCarrier = kAutoDetectCarrier;
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

    // 追跡番号そのもの、または各社の追跡URLを受け付ける（区切りは既存どおり）
    final tokens = splitTrackingTokens(_numberController.text);
    if (tokens.isEmpty) return;
    final parsedInputs = parseTrackingInputs(_numberController.text);

    // 配送会社は「自動判定」または明示選択。いずれも未選択になることはないが、
    // 防御的に null の場合は選択を促す。
    final carrier = _selectedCarrier;
    if (carrier == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配送会社を選択してください')),
        );
      }
      return;
    }
    final autoDetect = carrier == kAutoDetectCarrier;

    // 重複判定は正規化後の番号（parseTrackingInputs が正規化済み）で行う。
    // `1234-5678-9012` と `123456789012`、URL と素の番号を別物として
    // 二重登録しようとするのを防ぐ。
    // 同じ番号が複数回現れた場合は最初の入力（＝先に書かれた会社ヒント）を採用する。
    final inputsByNumber = <String, TrackingInput>{};
    for (final input in parsedInputs) {
      inputsByNumber.putIfAbsent(input.number, () => input);
    }
    final inputs = inputsByNumber.values.toList();

    // 入力全体から番号を1つも取り出せなかった分は「形式エラー」として集計する
    final invalidCount = tokens.length - parsedInputs.length;
    if (inputs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('追跡番号またはURLを認識できませんでした'),
          ),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final addTracking = ref.read(addTrackingProvider);
      final addTrackingAuto = ref.read(addTrackingAutoProvider);
      final nickname = _nicknameController.text.trim().isEmpty
          ? null
          : _nicknameController.text.trim();

      // 各番号を順次登録する（fetch成功時のみ登録する既存ロジックを維持）
      var successCount = 0;
      final failures = <String>[];
      for (final input in inputs) {
        // 会社決定の優先順位:
        // 1. 手動選択（既存挙動を維持）
        // 2. 追跡URLから推定した会社（各社への無駄な問い合わせと12桁の誤判定を避ける）
        // 3. 桁数からの自動判定
        final hintedCarrier = autoDetect ? input.carrierHint?.name : carrier;
        try {
          if (hintedCarrier != null) {
            await addTracking(
              trackingNumber: input.number,
              carrier: hintedCarrier,
              nickname: nickname,
            );
          } else {
            final detected = await addTrackingAuto(
              trackingNumber: input.number,
              nickname: nickname,
            );
            if (detected == null) {
              // どの会社でも情報を取得できなかった
              failures.add('配送会社を自動判定できませんでした');
              continue;
            }
          }
          successCount++;
        } catch (e) {
          failures.add(_friendlyErrorMessage(e));
        }
      }

      // 形式エラーでスキップした分も失敗として合算する
      if (invalidCount > 0) {
        failures.insert(0, '追跡番号またはURLを認識できませんでした');
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
                hintText: '1234-5678-9012 または 追跡URL',
                labelText: '追跡番号 / URL',
                helperText: '追跡番号または各社の追跡URL（複数は改行・カンマ区切り）',
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
///
/// URL を含む入力の解析は [parseTrackingInputs] が担う。分割規則を二重定義
/// しないよう、ここでは共通の [splitTrackingTokens] に委譲する。
List<String> splitTrackingNumbers(String input) => splitTrackingTokens(input);

/// 成功/失敗件数と失敗の内訳（最初の1-2件）をまとめたメッセージを組み立てる。
String buildAddResultSummary(int successCount, List<String> failures) {
  if (failures.isEmpty) {
    return '$successCount件すべて登録しました';
  }
  final detail = failures.take(2).join('、');
  final more = failures.length > 2 ? ' ほか${failures.length - 2}件' : '';
  return '$successCount件成功、${failures.length}件失敗しました（$detail$more）';
}
