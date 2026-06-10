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

    test('strips utf8 byte order marks from pasted or picked files', () {
      final result = CsvTools().parse('\uFEFFFront,Back\nQ,A');

      expect(result.inferredHeaders, ['Front', 'Back']);
      expect(result.dataRows().single, ['Q', 'A']);
    });

    test('does not throw for malformed quoted csv text', () {
      final result = CsvTools().parse('Front,Back\n"unterminated,A');

      expect(result.rows, isA<List<List<String>>>());
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

      expect(csv, contains('Front,Back'));
      expect(csv, contains('Q1,A1'));
      expect(csv, contains('Q2,"A,2"'));
      expect(csv, isNot(contains('geo')));
    });
  });
}
