import 'package:trackflow/domain/entities/carrier.dart';
import 'package:trackflow/domain/tracking_number.dart';

/// 追跡CSVをパースして有効なレコードのみ返す（テスト可能な純粋関数）。
///
/// - 1行目はヘッダーとしてスキップする
/// - CSVエスケープ（引用符内のカンマ・改行、`""` → `"`）に対応する
/// - 追跡番号が [TrackingNumberValidator.isValid] を満たし、
///   キャリアが [Carrier.values] の `name` と一致する行のみ採用する
/// - 無効な行・空行はスキップする
List<({String trackingNumber, String carrier, String? nickname})>
    parseTrackingsCsv(String csv) {
  final text = _stripBom(csv);
  final rows = _parseCsvRows(text);
  if (rows.isEmpty) return [];
  final dataRows = rows.sublist(1); // 1行目はヘッダー

  final result = <({String trackingNumber, String carrier, String? nickname})>[];
  for (final row in dataRows) {
    final record = _recordFromRow(row);
    if (record != null) result.add(record);
  }
  return result;
}

/// ヘッダー行と空行を除いたデータ行のうち、
/// 有効なレコードとして採用されなかった行数を返す。
///
/// インポート完了メッセージの「無効」件数の集計に使う。
int countInvalidTrackingsCsvRows(String csv) {
  final text = _stripBom(csv);
  final rows = _parseCsvRows(text);
  if (rows.length <= 1) return 0;

  var invalid = 0;
  for (final row in rows.sublist(1)) {
    if (row.every((field) => field.isEmpty)) continue; // 空行はカウントしない
    if (_recordFromRow(row) == null) invalid++;
  }
  return invalid;
}

String _stripBom(String csv) {
  return csv.startsWith('\uFEFF') ? csv.substring(1) : csv;
}

/// 1行をレコードへ変換する。無効な行は null を返す。
({String trackingNumber, String carrier, String? nickname})? _recordFromRow(
    List<String> row) {
  if (row.isEmpty) return null;
  final number = row[0];
  final carrierName = row.length > 1 ? row[1] : '';

  if (!TrackingNumberValidator.isValid(number)) return null;
  if (!Carrier.values.any((c) => c.name == carrierName)) return null;

  final nickname = row.length > 2 ? row[2] : null;
  return (
    trackingNumber: number,
    carrier: carrierName,
    nickname: (nickname == null || nickname.isEmpty) ? null : nickname,
  );
}

/// 引用符エスケープ対応のCSVパーサー。
///
/// - フィールド区切り: `,`
/// - 引用符 `"` で囲まれた値はカンマ・改行を含めることができ、
///   内部の `"` は `""` でエスケープする
/// - 行区切り: `\n` / `\r\n` / `\r`
List<List<String>> _parseCsvRows(String input) {
  final rows = <List<String>>[];
  final row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  final length = input.length;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(List.of(row));
    row.clear();
  }

  while (i < length) {
    final ch = input[i];

    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < length && input[i + 1] == '"') {
          field.write('"'); // "" → "
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(ch);
      i++;
      continue;
    }

    // 引用符外
    if (ch == '"') {
      inQuotes = true;
      i++;
      continue;
    }
    if (ch == ',') {
      endField();
      i++;
      continue;
    }
    if (ch == '\r') {
      endRow();
      if (i + 1 < length && input[i + 1] == '\n') {
        i += 2;
      } else {
        i++;
      }
      continue;
    }
    if (ch == '\n') {
      endRow();
      i++;
      continue;
    }
    field.write(ch);
    i++;
  }

  // 末尾に改行がない場合の最後の行
  if (field.isNotEmpty || row.isNotEmpty) {
    endRow();
  }
  return rows;
}