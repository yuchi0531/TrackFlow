import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trackflow/provider/settings_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final notifyDelivery = ref.watch(notifyDeliveryProvider);
    final notifyStatusChange = ref.watch(notifyStatusChangeProvider);
    final updateInterval = ref.watch(updateIntervalProvider);
    final setNotifyDelivery = ref.read(setNotifyDeliveryProvider);
    final setNotifyStatusChange = ref.read(setNotifyStatusChangeProvider);
    final setUpdateInterval = ref.read(setUpdateIntervalProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          _buildSectionHeader(context, '更新設定'),
          ListTile(
            leading: const Icon(Icons.update),
            title: const Text('自動更新間隔'),
            subtitle: Text(updateInterval),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showIntervalPicker(context, updateInterval, setUpdateInterval),
          ),
          const Divider(indent: 72),
          _buildSectionHeader(context, '通知'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('配達完了を通知'),
            subtitle: const Text('配達が完了したらプッシュ通知でお知らせします'),
            value: notifyDelivery,
            onChanged: setNotifyDelivery,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notification_important_outlined),
            title: const Text('ステータス変更を通知'),
            subtitle: const Text('配送状況に変化があったら通知します'),
            value: notifyStatusChange,
            onChanged: setNotifyStatusChange,
          ),
          const Divider(indent: 72),
          _buildSectionHeader(context, '情報'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('TrackFlowについて'),
            subtitle: const Text('バージョン 1.0.0'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'TrackFlow',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2026 TrackFlow',
                children: [
                  const Text(
                    'ヤマト運輸、佐川急便、日本郵便の3社を統合的に追跡できる荷物追跡アプリです。',
                  ),
                ],
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('プライバシーポリシー'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _showPrivacyPolicy(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  void _showIntervalPicker(BuildContext context, String current,
      void Function(String) onChanged) {
    final intervals = ['15分', '30分', '1時間', '3時間'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('自動更新間隔',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              ...intervals.map((interval) {
                return ListTile(
                  title: Text(interval),
                  trailing: interval == current
                      ? const Icon(Icons.check, color: Colors.blue)
                      : null,
                  onTap: () {
                    onChanged(interval);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('プライバシーポリシー'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _policySection('収集する情報', '本アプリは、お客様が入力した追跡番号とそのニックネームのみを端末内に保存します。個人を特定できる情報（氏名、住所、電話番号、メールアドレスなど）は一切収集しません。'),
              _policySection('データの保存', 'すべてのデータはお客様の端末内にのみ保存され、外部サーバーに送信されることはありません。アプリをアンインストールすると、すべてのデータが削除されます。'),
              _policySection('ネットワーク通信', '本アプリは追跡情報を取得するために、ヤマト運輸、佐川急便、日本郵便の公式Webサイトにアクセスします。これらの通信には追跡番号のみが送信され、個人情報は一切含まれません。'),
              _policySection('第三者提供', '本アプリは収集した情報を第三者に提供することは一切ありません。'),
              _policySection('お問い合わせ', '本プライバシーポリシーに関するお問い合わせは、アプリの開発者までご連絡ください。'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Widget _policySection(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(body, style: const TextStyle(fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }
}
