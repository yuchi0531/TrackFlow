import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trackflow/data/csv/csv_export.dart';
import 'package:trackflow/data/csv/csv_import.dart';
import 'package:trackflow/provider/background_provider.dart';
import 'package:trackflow/provider/database_provider.dart';
import 'package:trackflow/provider/settings_provider.dart';
import 'package:trackflow/provider/tracking_providers.dart';
import 'package:trackflow/provider/widget_snapshot_provider.dart';

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
    final notifyDeliveryDay = ref.watch(notifyDeliveryDayProvider);
    final updateInterval = ref.watch(updateIntervalProvider);
    final setNotifyDelivery = ref.read(setNotifyDeliveryProvider);
    final setNotifyStatusChange = ref.read(setNotifyStatusChangeProvider);
    final setNotifyDeliveryDay = ref.read(setNotifyDeliveryDayProvider);
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
            onChanged: (value) async {
              if (value) {
                // Android 13+ では通知権限が必須のため、有効化時にリクエスト
                final granted = await requestNotificationPermissions();
                if (!mounted) return;
                if (!granted) {
                  _showPermissionRequiredDialog(
                    this.context,
                    onGrantedAfter: setNotifyDelivery,
                  );
                  return;
                }
              }
              await setNotifyDelivery(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.event_available_outlined),
            title: const Text('配達予定日当日に通知'),
            subtitle: const Text('お届け予定日に通知します'),
            value: notifyDeliveryDay,
            onChanged: (value) async {
              if (value) {
                // Android 13+ では通知権限が必須のため、有効化時にリクエスト
                final granted = await requestNotificationPermissions();
                if (!mounted) return;
                if (!granted) {
                  _showPermissionRequiredDialog(
                    this.context,
                    onGrantedAfter: setNotifyDeliveryDay,
                  );
                  return;
                }
              }
              await setNotifyDeliveryDay(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notification_important_outlined),
            title: const Text('ステータス変更を通知'),
            subtitle: const Text('配送状況に変化があったら通知します'),
            value: notifyStatusChange,
            onChanged: (value) async {
              if (value) {
                // Android 13+ では通知権限が必須のため、有効化時にリクエスト
                final granted = await requestNotificationPermissions();
                if (!mounted) return;
                if (!granted) {
                  _showPermissionRequiredDialog(
                    this.context,
                    onGrantedAfter: setNotifyStatusChange,
                  );
                  return;
                }
              }
              await setNotifyStatusChange(value);
            },
          ),
          const Divider(indent: 72),
          _buildSectionHeader(context, 'データ'),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('CSVエクスポート'),
            subtitle: const Text('追跡一覧をCSVファイルに書き出します'),
            onTap: _exportCsv,
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('CSVインポート'),
            subtitle: const Text('CSVファイルから追跡番号を一括登録します'),
            onTap: _importCsv,
          ),
          const Divider(indent: 72),
          _buildSectionHeader(context, '情報'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('TrackFlowについて'),
            subtitle: const Text('バージョン 0.0.7'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'TrackFlow',
                applicationVersion: '0.0.7',
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

  /// 追跡一覧（アクティブな追跡＋最新履歴）をCSVファイルに書き出す。
  Future<void> _exportCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = await ref.read(databaseProvider.future);
      final saved = await db.getAllActive();
      final latestHistories = await db.getAllLatestHistories();
      final csv = buildTrackingsCsv(saved, latestHistories);

      final now = DateTime.now();
      // Android/iOS では file_picker の saveFile に bytes が必須。
      // file_picker がSAF経由で書き込みまで行い、保存先のパスを返す。
      final path = await FilePicker.saveFile(
        dialogTitle: 'CSVを保存',
        fileName: 'trackflow_${_dateStamp(now)}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: utf8.encode(csv),
      );
      if (path == null) return; // キャンセル

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('エクスポートしました: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('エクスポートに失敗しました: $e')),
      );
    }
  }

  /// CSVファイルから追跡番号を一括登録する。
  ///
  /// 取得（fetch）は行わない。バックグラウンドの定期タスクが後から
  /// 追跡情報を取得するため、ここでは DB への登録のみ行う。
  Future<void> _importCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (file == null) return; // キャンセル
      // 12.0.0-beta 以降は PlatformFile.readAsBytes() でデータを読み込む
      final bytes = await file.readAsBytes();
      final csv = utf8.decode(bytes);
      final records = parseTrackingsCsv(csv);
      final invalidCount = countInvalidTrackingsCsvRows(csv);

      final db = await ref.read(databaseProvider.future);
      var imported = 0;
      var duplicates = 0;
      for (final record in records) {
        final existing = await db.findByTrackingNumber(
          record.trackingNumber,
          record.carrier,
        );
        if (existing != null) {
          duplicates++;
          continue;
        }
        await db.insertTracking(
          record.trackingNumber,
          record.carrier,
          nickname: record.nickname,
        );
        imported++;
      }
      ref.invalidate(trackingListProvider);
      // インポート直後は一覧が未表示（設定タブ）でウィジェット更新が走らないため、
      // ここでホームウィジェットのスナップショットも更新する（fire-and-forget）。
      unawaited(updateWidgetSnapshot(db: db));

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$imported件インポートしました（重複・無効 '
            '${duplicates + invalidCount}件スキップ）',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('インポートに失敗しました: $e')),
      );
    }
  }

  /// `yyyyMMdd` 形式の日付文字列（エクスポートファイル名に使用）。
  String _dateStamp(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  void _showPermissionRequiredDialog(BuildContext context,
      {Future<void> Function(bool)? onGrantedAfter}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('通知の許可が必要です'),
        content: const Text(
          '通知を受け取るには、システム設定からアプリの通知を許可してください。\n\n'
          '設定 → アプリ → TrackFlow → 通知 → 通知を許可',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // システムの通知設定画面を開いて権限を手動で付与してもらう
              final opened = await openNotificationSettings();
              if (!opened || onGrantedAfter == null) return;
              // 設定画面から戻った後に権限が実際に付与されたか再確認する。
              // 付与されていない場合（ユーザーが許可しなかった場合）は
              // トグルをONにしない。
              final granted = await areNotificationsEnabled();
              if (granted) {
                await onGrantedAfter(true);
              }
            },
            child: const Text('設定を開く'),
          ),
        ],
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
