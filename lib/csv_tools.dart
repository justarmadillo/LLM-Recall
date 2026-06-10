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
  static const delimiters = [',', ';', '\t'];

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
    return const CsvEncoder().convert(rows);
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
    final List<List<dynamic>> parsed;
    try {
      parsed = CsvDecoder(
        fieldDelimiter: delimiter,
        dynamicTyping: false,
      ).convert(input);
    } on FormatException {
      return const [];
    }
    return parsed
        .map((row) => row.map((cell) => cell?.toString() ?? '').toList())
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
        (index) => index < row.length ? row[index].trim() : '',
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
    final knownHeader = first.any((cell) {
      final lower = cell.toLowerCase();
      return lower == 'front' ||
          lower == 'back' ||
          lower == 'question' ||
          lower == 'answer' ||
          lower == 'tags' ||
          lower == 'extra';
    });

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
    if (knownHeader) {
      score += 2;
    }
    return score >= 3;
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

String _cleanHeader(String value, int index) {
  final cleaned = value.trim();
  if (cleaned.isEmpty) {
    return 'Column ${index + 1}';
  }
  return cleaned;
}
