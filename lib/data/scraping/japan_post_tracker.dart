import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:trackflow/core/constants/carrier_urls.dart';
import 'package:trackflow/domain/entities/tracking_event.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/domain/entities/carrier.dart';

import 'carrier_tracker.dart';

/// 日本郵便の追跡をスクレイピングするトラッカー
class JapanPostTracker implements CarrierTracker {
  @override
  String get carrierId => 'japanPost';

  @override
  Future<TrackingInfo> fetch(String trackingNumber) async {
    final uri = Uri.parse(CarrierUrls.japanPostTrackingUrl).replace(
      queryParameters: {
        'reqCodeNo1': trackingNumber,
        'searchKind': 'S004',
        'locale': 'ja',
      },
    );

    final response = await http.get(
      uri,
      headers: {'User-Agent': CarrierUrls.userAgent},
    );

    if (response.statusCode != 200) {
      throw TrackerException(
        type: TrackerErrorType.networkFailure,
        message: 'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    return parse(response.body, trackingNumber);
  }

  @override
  TrackingInfo parse(String html, String trackingNumber) {
    final doc = html_parser.parse(html);
    final tables = doc.querySelectorAll('table.tableType01');

    if (tables.length < 2) {
      throw TrackerException(
        type: TrackerErrorType.notFound,
        message: 'お問い合わせ番号が見つかりません',
      );
    }

    // 商品種別の取得（1つ目のテーブル）
    String? itemType;
    final headerCells = tables[0].querySelectorAll('tbody td');
    if (headerCells.length >= 2) {
      final text = headerCells[1].text.trim();
      itemType = text.isEmpty ? null : text;
    }

    // 追跡イベントのパース（2つ目のテーブル）
    final rows = tables[1].querySelectorAll('tbody tr');
    final events = <TrackingEvent>[];

    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 4) continue;

      final rawDate = cells[0].text.trim();
      final status = cells[1].text.trim();
      final location = cells[3].text.trim();

      if (rawDate.isEmpty && status.isEmpty) continue;

      events.add(TrackingEvent(
        rawDate: rawDate,
        date: _parseDate(rawDate),
        status: status,
        location: location.isNotEmpty ? location : null,
      ));
    }

    if (events.isEmpty) {
      throw TrackerException(
        type: TrackerErrorType.notFound,
        message: '追跡情報が見つかりません',
      );
    }

    return TrackingInfo(
      trackingNumber: trackingNumber,
      carrier: Carrier.japanPost,
      itemType: itemType,
      currentStatus: events.last.status,
      estimatedDelivery: null,
      events: events,
      lastUpdated: DateTime.now(),
    );
  }

  DateTime? _parseDate(String raw) {
    try {
      final parts = raw.split(RegExp(r'[/ :]'));
      if (parts.length >= 3) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        if (parts.length >= 5) {
          final hour = int.parse(parts[3]);
          final minute = int.parse(parts[4]);
          return DateTime(year, month, day, hour, minute);
        }
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return null;
  }
}
