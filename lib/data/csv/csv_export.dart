import 'package:trackflow/data/local/database.dart';

/// 追跡一覧をCSVテキストに変換する（テスト可能な純粋関数）。
///
/// [saved] にはアクティブな追跡のみを渡す（非アクティブな追跡は無視される）。
/// [latestHistories] は `'{trackingNumber}_{carrier}'` をキーとする最新履歴の
/// マップ（[AppDatabase.getAllLatestHistories] の戻り値と同じ形式）。
///
/// 出力形式:
/// - ヘッダー: `trackingNumber,carrier,nickname,currentStatus,estimatedDelivery,fetchedAt`
/// - 各データ行: アクティブな追跡ごとに最新履歴のステータス情報を付与する。
///   履歴が無い追跡は currentStatus / estimatedDelivery / fetchedAt が空になる。
/// - 値に `"` `,` 改行が含まれる場合は `"` で囲み、内部の `"` を `""` に
///   エスケープする（RFC 4180風）。
String buildTrackingsCsv(
  List<SavedTracking> saved,
  Map<String, TrackingHistory> latestHistories,
) {
  final buffer = StringBuffer();
  buffer.writeln(
    [
      'trackingNumber',
      'carrier',
      'nickname',
      'currentStatus',
      'estimatedDelivery',
      'fetchedAt',
    ].map(_escapeField).join(','),
  );

  for (final item in saved) {
    if (!item.isActive) continue; // アクティブな追跡のみ出力
    final history = latestHistories['${item.trackingNumber}_${item.carrier}'];

    final row = [
      _escapeField(item.trackingNumber),
      _escapeField(item.carrier),
      _escapeField(item.nickname ?? ''),
      _escapeField(history?.currentStatus ?? ''),
      _escapeField(history?.estimatedDelivery ?? ''),
      _escapeField(history == null ? '' : _formatDateTime(history.fetchedAt)),
    ].join(',');
    buffer.writeln(row);
  }

  return buffer.toString();
}

/// CSVフィールドをエスケープする。
///
/// `"` `,` 改行を含む値は `"` で囲み、内部の `"` は `""` に置き換える。
String _escapeField(String value) {
  final needsQuoting = value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuoting) return value;
  return '"${value.replaceAll('"', '""')}"';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 日時を `yyyy-MM-dd HH:mm:ss` 形式で表示する（CSVでの可読性のため）。
String _formatDateTime(DateTime dt) =>
    '${dt.year}-${_two(dt.month)}-${_two(dt.day)} '
    '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';