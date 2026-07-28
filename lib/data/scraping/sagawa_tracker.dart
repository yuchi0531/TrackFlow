import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:trackflow/core/constants/carrier_urls.dart';
import 'package:trackflow/domain/entities/tracking_event.dart';
import 'package:trackflow/domain/entities/tracking_info.dart';
import 'package:trackflow/domain/entities/carrier.dart';

import 'carrier_tracker.dart';

/// 佐川急便の追跡をスクレイピングするトラッカー
class SagawaTracker implements CarrierTracker {
  @override
  String get carrierId => 'sagawa';

  @override
  Future<TrackingInfo> fetch(String trackingNumber) async {
    final uri = Uri.parse(CarrierUrls.sagawaTrackingUrl);

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': CarrierUrls.userAgent,
      },
      body: 'okurijoNo=$trackingNumber',
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

    // 現在ステータスと配達予定日
    String currentStatus = '';
    String? estimatedDelivery;
    final statusTables = doc.querySelectorAll('table.ttl02');
    if (statusTables.isNotEmpty) {
      final ths = statusTables[0]
          .querySelectorAll('th')
          .map((e) => e.text.trim())
          .toList();
      if (ths.length >= 3) {
        currentStatus = ths[2];
      }

      final td = statusTables[0].querySelector('td');
      if (td != null) {
        final raw = td.text.trim();
        estimatedDelivery = _extractValueAfter('配達予定日', raw);
      }
    }

    // 追跡イベント
    final events = <TrackingEvent>[];
    for (final table in doc.querySelectorAll('table.table_okurijo_detail2')) {
      final headerText =
          table.querySelectorAll('th').map((e) => e.text).join();
      if (!headerText.contains('荷物状況') ||
          !headerText.contains('担当営業所')) {
        continue;
      }

      for (final row in table.querySelectorAll('tr')) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 3) continue;

        var statusRaw = cells[0].text.trim();
        final dateRaw = cells[1].text.trim();
        final branch = cells[2].text.trim();

        final status = statusRaw
            .replaceAll(RegExp(r'[↓⇒　\u{3000}]', unicode: true), '')
            .trim();

        if (status.isEmpty && dateRaw.isEmpty) continue;

        events.add(TrackingEvent(
          rawDate: dateRaw,
          date: _parseDate(dateRaw),
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

    if (currentStatus.isEmpty) {
      currentStatus = events.last.status;
    }

    return TrackingInfo(
      trackingNumber: trackingNumber,
      carrier: Carrier.sagawa,
      itemType: null,
      currentStatus: currentStatus,
      estimatedDelivery: estimatedDelivery,
      events: events,
      lastUpdated: DateTime.now(),
    );
  }

  static String? _extractValueAfter(String label, String text) {
    final index = text.indexOf(label);
    if (index == -1) return null;

    final after = text.substring(index + label.length);
    final value = after
        .replaceAll(RegExp(r'^[:：　\t\n]+'), '')
        .trim();

    return value.isEmpty ? null : value;
  }

  DateTime? _parseDate(String raw) {
    try {
      final year = DateTime.now().year;
      final parts = '$year/$raw'.split(RegExp(r'[/ :]'));
      if (parts.length >= 5) {
        final y = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        final hour = int.parse(parts[3]);
        final minute = int.parse(parts[4]);
        return DateTime(y, month, day, hour, minute);
      }
    } catch (_) {}
    return null;
  }
}
