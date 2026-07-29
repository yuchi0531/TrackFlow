import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trackflow/data/repositories/tracking_repository_impl.dart';
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
    final number = _numberController.text.trim();
    if (number.isEmpty || _isSubmitting) return;

    final carrier = _selectedCarrier ??
        TrackingRepositoryImpl.detectCarrier(number)?.name ??
        'yamato';

    setState(() => _isSubmitting = true);

    try {
      final addTracking = ref.read(addTrackingProvider);
      await addTracking(
        trackingNumber: number,
        carrier: carrier,
        nickname: _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
      );

      ref.invalidate(trackingListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('追跡を開始しました')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSubmit = _numberController.text.trim().isNotEmpty && !_isSubmitting;
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
              decoration: const InputDecoration(
                hintText: '1234-5678-9012',
                labelText: '追跡番号',
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
