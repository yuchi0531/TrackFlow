import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:trackflow/core/constants/carrier_urls.dart';
import 'package:trackflow/domain/entities/tracking_event.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/domain/entities/carrier.dart';

import 'carrier_tracker.dart';

/// ヤマト運輸の追跡をスクレイピングするトラッカー
class YamatoTracker implements CarrierTracker {
  @override
  String get carrierId => 'yamato';

  @override
  Future<TrackingInfo> fetch(String trackingNumber) async {
    final uri = Uri.parse(CarrierUrls.yamatoTrackingUrl);

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': CarrierUrls.userAgent,
        },
        body: 'number00=1&number01=$trackingNumber',
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw TrackerException(
          type: TrackerErrorType.networkFailure,
          message: 'HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      return parse(response.body, trackingNumber);
    } on TrackerException {
      rethrow;
    } on Exception catch (e) {
      throw TrackerException(
        type: TrackerErrorType.networkFailure,
        message: 'サーバーに接続できません: $e',
      );
    }
  }

  @override
  TrackingInfo parse(String html, String trackingNumber) {
    final reconstructed = _reconstructHTML(html);
    if (reconstructed.isEmpty) {
      throw TrackerException(
        type: TrackerErrorType.parseFailure,
        message: 'ページ構造の解析に失敗しました',
      );
    }

    final doc = html_parser.parse(reconstructed);
    final tables = doc.querySelectorAll('table');

    // 追跡イベントの抽出
    final events = <TrackingEvent>[];
    for (final table in tables) {
      final thText = table.querySelectorAll('th').map((e) => e.text).join();
      if (!thText.contains('荷物状況') || !thText.contains('担当店名')) continue;

      for (final row in table.querySelectorAll('tr')) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 4) continue;

        final status = cells[0].text.trim();
        final dateStr = cells[1].text.trim();
        final timeStr = cells[2].text.trim();
        final branch = cells[3].text.trim();

        final rawDate = [dateStr, timeStr]
            .where((s) => s.isNotEmpty)
            .join(' ');
        if (rawDate.isEmpty && status.isEmpty) continue;

        events.add(TrackingEvent(
          rawDate: rawDate,
          date: _parseDate(rawDate),
          status: status,
          location: branch.isNotEmpty ? branch : null,
        ));
      }
      break;
    }

    if (events.isEmpty) {
      throw TrackerException(
        type: TrackerErrorType.notFound,
        message: 'お問い合わせ番号が見つかりません',
      );
    }

    // 商品名と配達予定日
    String? itemType;
    String? estimated;
    for (final table in tables) {
      final ths = table.querySelectorAll('th').map((e) => e.text).toList();
      final deliveryIndex = ths.indexWhere((t) => t.contains('お届け予定日時'));
      final itemIndex = ths.indexWhere((t) => t.contains('商品名'));

      if (deliveryIndex == -1 || itemIndex == -1) continue;

      for (final row in table.querySelectorAll('tr')) {
        final cells = row.querySelectorAll('td');
        if (cells.length <
            (deliveryIndex > itemIndex ? deliveryIndex : itemIndex) + 1) {
          continue;
        }

        final item = cells[itemIndex].text.trim();
        final est = cells[deliveryIndex].text.trim();

        if (item.isNotEmpty) itemType = item;
        if (est.isNotEmpty) {
          estimated = est.replaceAll('\u{3000}', ' ');
        }
        break;
      }
      break;
    }

    return TrackingInfo(
      trackingNumber: trackingNumber,
      carrier: Carrier.yamato,
      itemType: itemType,
      currentStatus: events.last.status,
      estimatedDelivery: estimated,
      events: events,
      lastUpdated: DateTime.now(),
    );
  }

  static String _reconstructHTML(String html) {
    final pattern = RegExp(r"swd\.writeln\('([^']*)'\)");
    final matches = pattern.allMatches(html);

    final raw = matches.map((m) => m.group(1) ?? '').join();
    if (raw.isEmpty) return '';

    var cleaned = raw
        .replaceAll('\\<', '<')
        .replaceAll('\\>', '>')
        .replaceAll('\\/', '/');

    final tagsToStrip = [
      RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false),
      RegExp(r'</?html[^>]*>', caseSensitive: false),
      RegExp(r'</?head[^>]*>', caseSensitive: false),
      RegExp(r'</?body[^>]*>', caseSensitive: false),
      RegExp(r'<title[^>]*>[\s\S]*?</title>', caseSensitive: false),
      RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
      RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
      RegExp(r'<!--[\s\S]*?-->'),
    ];

    for (final pattern in tagsToStrip) {
      cleaned = cleaned.replaceAll(pattern, '');
    }

    return cleaned;
  }

  DateTime? _parseDate(String raw) {
    try {
      final now = DateTime.now();
      final year = now.year;
      final parts = '$year/$raw'.split(RegExp(r'[/ :]'));
      if (parts.length >= 3) {
        final y = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        if (parts.length >= 5) {
          final hour = int.parse(parts[3]);
          final minute = int.parse(parts[4]);
          final dt = DateTime(y, month, day, hour, minute);
          // 未来の日付がパースされた場合、年を1つ戻す（年跨ぎ対応）
          return dt.isAfter(now) ? DateTime(y - 1, month, day, hour, minute) : dt;
        }
        final dt = DateTime(y, month, day);
        return dt.isAfter(now) ? DateTime(y - 1, month, day) : dt;
      }
    } catch (_) {}
    return null;
  }
}
