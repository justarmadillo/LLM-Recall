import 'package:flutter_test/flutter_test.dart';
import 'package:preanki/csv_tools.dart';

void main() {
  group('CsvTools', () {
    test('parses quoted commas, escaped quotes, and multiline values', () {
      final result = CsvTools().parse(
        'Front,Back\n'
        '"What is, CSV?","A ""comma"" format"\n'
        '"Line\nbreak",Answer',
      );

      expect(result.delimiter, ',');
      expect(result.hasHeader, isTrue);
      expect(result.inferredHeaders, ['Front', 'Back']);
      expect(result.dataRows(), hasLength(2));
      expect(result.dataRows().first, ['What is, CSV?', 'A "comma" format']);
      expect(result.dataRows().last.first, 'Line\nbreak');
    });

    test('detects semicolon delimiter', () {
      final result = CsvTools().parse('Question;Answer\nCapital?;Paris');

      expect(result.delimiter, ';');
      expect(result.inferredHeaders, ['Question', 'Answer']);
      expect(result.dataRows().single, ['Capital?', 'Paris']);
    });

    test('detects tab and pipe delimiters', () {
      final tab = CsvTools().parse('Term\tDefinition\nCell\tSmall unit');
      final pipe = CsvTools().parse('Front|Back\nQ|A');

      expect(tab.delimiter, '\t');
      expect(tab.inferredHeaders, ['Term', 'Definition']);
      expect(tab.dataRows().single, ['Cell', 'Small unit']);
      expect(pipe.delimiter, '|');
      expect(pipe.dataRows().single, ['Q', 'A']);
    });

    test('strips utf8 byte order marks from pasted or picked files', () {
      final result = CsvTools().parse('\uFEFFFront,Back\nQ,A');

      expect(result.inferredHeaders, ['Front', 'Back']);
      expect(result.dataRows().single, ['Q', 'A']);
    });

    test('decodes utf16 and windows single-byte files', () {
      final tools = CsvTools();
      final utf16Bytes = _utf16LeWithBom('Front\tBack\nQuestion\tRéponse');
      final windows1252Bytes = [
        ...'Front,Back\nQ,'.codeUnits,
        0x93,
        ...'smart'.codeUnits,
        0x94,
      ];

      expect(tools.parse(tools.decodeBytes(utf16Bytes)).dataRows().single, [
        'Question',
        'Réponse',
      ]);
      expect(
        tools.parse(tools.decodeBytes(windows1252Bytes)).dataRows().single,
        ['Q', '“smart”'],
      );
    });

    test('does not throw for malformed quoted csv text', () {
      final result = CsvTools().parse('Front,Back\n"unterminated,A');

      expect(result.delimiter, ',');
      expect(result.inferredHeaders, ['Front', 'Back']);
      expect(result.dataRows().single, ['unterminated,A', '']);
    });

    test('preserves intentional whitespace inside imported fields', () {
      final result = CsvTools().parse(
        'Front,Back\n'
        '"  code\n'
        '  line  "," answer "',
      );

      expect(result.dataRows().single, ['  code\n  line  ', ' answer ']);
    });

    test('is conservative for short content rows without known headers', () {
      final result = CsvTools().parse('Cell,Mitochondria\nDNA,Nucleus');

      expect(result.hasHeader, isFalse);
      expect(result.dataRows(), [
        ['Cell', 'Mitochondria'],
        ['DNA', 'Nucleus'],
      ]);
    });

    test('exports selected fields with a header row', () {
      final csv = CsvTools().exportRows(
        headers: const ['Front', 'Back', 'Tags'],
        cards: const [
          {'Front': 'Q1', 'Back': 'A1', 'Tags': 'geo'},
          {'Front': 'Q2', 'Back': 'A,2', 'Tags': 'science'},
        ],
        exportFields: const ['Front', 'Back'],
        includeHeader: true,
      );

      expect(csv, contains('"Front","Back"'));
      expect(csv, contains('"Q1","A1"'));
      expect(csv, contains('"Q2","A,2"'));
      expect(csv, isNot(contains('geo')));
    });

    test('quotes every exported field so Anki cannot drop # rows', () {
      final csv = CsvTools().exportRows(
        headers: const ['Front', 'Back'],
        cards: const [
          {'Front': '# heading question', 'Back': 'answer'},
        ],
        exportFields: const ['Front', 'Back'],
        includeHeader: false,
      );

      // Unquoted lines starting with '#' are treated as comments by Anki's
      // CSV importer; always-quoted output keeps the row importable.
      expect(csv.trim(), '"# heading question","answer"');
    });
  });
}

List<int> _utf16LeWithBom(String value) {
  final bytes = <int>[0xFF, 0xFE];
  for (final codeUnit in value.codeUnits) {
    bytes
      ..add(codeUnit & 0xFF)
      ..add(codeUnit >> 8);
  }
  return bytes;
}
