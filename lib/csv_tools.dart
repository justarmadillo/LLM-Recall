import 'dart:convert';

import 'package:csv/csv.dart';

class CsvImportResult {
  const CsvImportResult({
    required this.delimiter,
    required this.rows,
    required this.hasHeader,
  });

  final String delimiter;
  final List<List<String>> rows;
  final bool hasHeader;

  List<String> get inferredHeaders {
    if (rows.isEmpty) {
      return const [];
    }
    if (hasHeader) {
      return rows.first
          .asMap()
          .entries
          .map((entry) => _cleanHeader(entry.value, entry.key))
          .toList();
    }
    return List.generate(rows.first.length, (index) => 'Column ${index + 1}');
  }

  List<List<String>> dataRows({bool? headerOverride}) {
    final useHeader = headerOverride ?? hasHeader;
    if (rows.isEmpty) {
      return const [];
    }
    return useHeader ? rows.skip(1).toList() : rows;
  }
}

class CsvTools {
  static const delimiters = [',', ';', '\t', '|'];

  String decodeBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      return '';
    }
    if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (_startsWith(bytes, const [0xFF, 0xFE])) {
      return _decodeUtf16(bytes, littleEndian: true, offset: 2);
    }
    if (_startsWith(bytes, const [0xFE, 0xFF])) {
      return _decodeUtf16(bytes, littleEndian: false, offset: 2);
    }

    final utf16Guess = _guessUtf16Endianness(bytes);
    if (utf16Guess != null) {
      return _decodeUtf16(bytes, littleEndian: utf16Guess);
    }

    try {
      return utf8.decode(bytes);
    } on FormatException {
      final malformedUtf8 = utf8.decode(bytes, allowMalformed: true);
      final replacementCount = '\uFFFD'.allMatches(malformedUtf8).length;
      if (replacementCount > 0 && _looksLikeSingleByteText(bytes)) {
        return _decodeWindows1252(bytes);
      }
      return malformedUtf8;
    }
  }

  CsvImportResult parse(String input) {
    final normalized = input
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    if (normalized.trim().isEmpty) {
      return const CsvImportResult(delimiter: ',', rows: [], hasHeader: false);
    }

    final parsedByDelimiter = <String, List<List<String>>>{};
    for (final delimiter in delimiters) {
      parsedByDelimiter[delimiter] = _parseWithDelimiter(normalized, delimiter);
    }
    final delimiter = _bestDelimiter(parsedByDelimiter);
    final rows = _normalizeRows(parsedByDelimiter[delimiter] ?? const []);

    return CsvImportResult(
      delimiter: delimiter,
      rows: rows,
      hasHeader: _detectHeader(rows),
    );
  }

  String exportRows({
    required List<String> headers,
    required List<Map<String, String>> cards,
    required List<String> exportFields,
    required bool includeHeader,
  }) {
    final rows = <List<String>>[];
    if (includeHeader) {
      rows.add(
        exportFields.map((field) {
          final index = headers.indexOf(field);
          return index >= 0 ? headers[index] : field;
        }).toList(),
      );
    }
    for (final card in cards) {
      rows.add(exportFields.map((field) => card[field] ?? '').toList());
    }
    // Quote every field so rows can never be misread downstream — Anki treats
    // unquoted lines starting with '#' as comments and would drop those cards.
    return const CsvEncoder(quoteMode: QuoteMode.always).convert(rows);
  }

  List<Map<String, String>> rowsToCards({
    required List<List<String>> rows,
    required List<String> fieldNames,
  }) {
    return rows.map((row) {
      final fields = <String, String>{};
      for (var index = 0; index < fieldNames.length; index += 1) {
        fields[fieldNames[index]] = index < row.length ? row[index] : '';
      }
      return fields;
    }).toList();
  }

  List<List<String>> _parseWithDelimiter(String input, String delimiter) {
    try {
      final parsed = CsvDecoder(
        fieldDelimiter: delimiter,
        dynamicTyping: false,
      ).convert(input);
      return parsed
          .map((row) => row.map((cell) => cell?.toString() ?? '').toList())
          .where((row) => row.any((cell) => cell.trim().isNotEmpty))
          .toList();
    } on FormatException {
      return _relaxedParseWithDelimiter(input, delimiter);
    }
  }

  List<List<String>> _relaxedParseWithDelimiter(
    String input,
    String delimiter,
  ) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    var quoteStartedCell = false;

    void endCell() {
      row.add(cell.toString());
      cell.clear();
      quoteStartedCell = false;
    }

    void endRow() {
      endCell();
      rows.add(row);
      row = <String>[];
    }

    for (var index = 0; index < input.length; index += 1) {
      final char = input[index];
      final next = index + 1 < input.length ? input[index + 1] : null;

      if (char == '"') {
        if (inQuotes && next == '"') {
          cell.write('"');
          index += 1;
        } else if (!inQuotes && cell.toString().trim().isEmpty) {
          inQuotes = true;
          quoteStartedCell = true;
          if (cell.length > 0) {
            cell.clear();
          }
        } else if (inQuotes) {
          inQuotes = false;
        } else {
          cell.write(char);
        }
      } else if (!inQuotes && char == delimiter) {
        endCell();
      } else if (!inQuotes && char == '\n') {
        endRow();
      } else {
        if (!quoteStartedCell || char != '\r') {
          cell.write(char);
        }
      }
    }
    if (cell.length > 0 || row.isNotEmpty) {
      endRow();
    }

    return rows
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();
  }

  List<List<String>> _normalizeRows(List<List<String>> rows) {
    if (rows.isEmpty) {
      return const [];
    }
    final maxColumns = rows
        .map((row) => row.length)
        .fold<int>(0, (max, length) => length > max ? length : max);
    return rows.map((row) {
      return List.generate(
        maxColumns,
        (index) => index < row.length ? row[index] : '',
      );
    }).toList();
  }

  String _bestDelimiter(Map<String, List<List<String>>> parsed) {
    var bestDelimiter = ',';
    var bestScore = -1;
    for (final entry in parsed.entries) {
      final rows = entry.value;
      if (rows.isEmpty) {
        continue;
      }
      final columnCounts = rows.map((row) => row.length).toList();
      final multiColumnRows = columnCounts.where((count) => count > 1).length;
      final maxColumns = columnCounts.fold<int>(
        0,
        (max, count) => count > max ? count : max,
      );
      final expected = _mode(columnCounts);
      final consistency = columnCounts
          .where((count) => count == expected)
          .length;
      final score = (multiColumnRows * 10) + (maxColumns * 3) + consistency;
      if (score > bestScore) {
        bestScore = score;
        bestDelimiter = entry.key;
      }
    }
    return bestDelimiter;
  }

  int _mode(List<int> values) {
    final counts = <int, int>{};
    for (final value in values) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  bool _detectHeader(List<List<String>> rows) {
    if (rows.length < 2 || rows.first.isEmpty) {
      return false;
    }
    final first = rows.first.map((cell) => cell.trim()).toList();
    final second = rows[1].map((cell) => cell.trim()).toList();
    final uniqueLabels = first.toSet().length == first.length;
    final allShort = first.every(
      (cell) => cell.isNotEmpty && cell.length <= 40,
    );
    final allLabelLike = first.every(_isLabelLike);
    final firstNumericCount = first.where(_looksNumeric).length;
    final secondContentCount = second
        .where((cell) => cell.length > 40 || cell.contains('?'))
        .length;
    final knownHeaderCount = first.where((cell) {
      final lower = cell.toLowerCase();
      return lower == 'front' ||
          lower == 'back' ||
          lower == 'text' ||
          lower == 'term' ||
          lower == 'definition' ||
          lower == 'prompt' ||
          lower == 'question' ||
          lower == 'answer' ||
          lower == 'response' ||
          lower == 'tags' ||
          lower == 'tag' ||
          lower == 'cloze' ||
          lower == 'note' ||
          lower == 'notes' ||
          lower == 'explanation' ||
          lower == 'extra';
    }).length;

    var score = 0;
    if (uniqueLabels) {
      score += 1;
    }
    if (allShort && allLabelLike) {
      score += 1;
    }
    if (firstNumericCount == 0) {
      score += 1;
    }
    if (secondContentCount > 0) {
      score += 1;
    }
    if (knownHeaderCount > 0) {
      score += 2;
    }
    return knownHeaderCount > 0 ? score >= 3 : score >= 4;
  }

  bool _isLabelLike(String value) {
    if (value.isEmpty || value.contains('\n')) {
      return false;
    }
    return RegExp(r'^[\p{L}\p{N}_\-\s/]+$', unicode: true).hasMatch(value);
  }

  bool _looksNumeric(String value) {
    return double.tryParse(value.replaceAll(',', '.')) != null;
  }
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (var index = 0; index < prefix.length; index += 1) {
    if (bytes[index] != prefix[index]) {
      return false;
    }
  }
  return true;
}

String _decodeUtf16(
  List<int> bytes, {
  required bool littleEndian,
  int offset = 0,
}) {
  final units = <int>[];
  for (var index = offset; index + 1 < bytes.length; index += 2) {
    final first = bytes[index];
    final second = bytes[index + 1];
    final unit = littleEndian ? first | (second << 8) : (first << 8) | second;
    if (unit != 0xFEFF) {
      units.add(unit);
    }
  }
  return String.fromCharCodes(units);
}

bool? _guessUtf16Endianness(List<int> bytes) {
  final sampleLength = bytes.length < 512 ? bytes.length : 512;
  if (sampleLength < 8) {
    return null;
  }
  var evenNulls = 0;
  var oddNulls = 0;
  for (var index = 0; index < sampleLength; index += 1) {
    if (bytes[index] != 0) {
      continue;
    }
    if (index.isEven) {
      evenNulls += 1;
    } else {
      oddNulls += 1;
    }
  }
  final threshold = sampleLength ~/ 8;
  if (oddNulls > threshold && oddNulls > evenNulls * 3) {
    return true;
  }
  if (evenNulls > threshold && evenNulls > oddNulls * 3) {
    return false;
  }
  return null;
}

bool _looksLikeSingleByteText(List<int> bytes) {
  if (bytes.any((byte) => byte == 0)) {
    return false;
  }
  final highBytes = bytes.where((byte) => byte >= 0x80).length;
  return highBytes > 0 && highBytes <= bytes.length * 0.35;
}

String _decodeWindows1252(List<int> bytes) {
  return String.fromCharCodes(
    bytes.map((byte) {
      if (byte < 0x80 || byte >= 0xA0) {
        return byte;
      }
      return _windows1252CodePoints[byte - 0x80] ?? byte;
    }),
  );
}

const _windows1252CodePoints = <int?>[
  0x20AC,
  null,
  0x201A,
  0x0192,
  0x201E,
  0x2026,
  0x2020,
  0x2021,
  0x02C6,
  0x2030,
  0x0160,
  0x2039,
  0x0152,
  null,
  0x017D,
  null,
  null,
  0x2018,
  0x2019,
  0x201C,
  0x201D,
  0x2022,
  0x2013,
  0x2014,
  0x02DC,
  0x2122,
  0x0161,
  0x203A,
  0x0153,
  null,
  0x017E,
  0x0178,
];

String _cleanHeader(String value, int index) {
  final cleaned = value.trim();
  if (cleaned.isEmpty) {
    return 'Column ${index + 1}';
  }
  return cleaned;
}
