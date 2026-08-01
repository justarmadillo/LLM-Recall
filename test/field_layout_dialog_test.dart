import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preanki/models.dart';
import 'package:preanki/widgets/field_layout_dialog.dart';

void main() {
  testWidgets('returns ordered prompt and front-and-back fields', (
    tester,
  ) async {
    FieldLayoutResult? savedResult;
    final session = _session(
      fieldNames: const ['Front', 'Back', 'Extra'],
      frontField: 'Front',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                savedResult = await showFieldLayoutDialog(
                  context,
                  session: session,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Arrange fields'), findsOneWidget);
    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('Back 1'), findsOneWidget);
    expect(find.text('Back 2'), findsOneWidget);
    expect(find.text('Front & back (prompt)'), findsOneWidget);
    expect(find.text('Back only'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('field-layout-drag-Extra')),
      findsOneWidget,
    );

    final reorderable = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    reorderable.onReorderItem!(2, 1);
    await tester.pump();
    final extraFrontToggle = find.byKey(
      const ValueKey('field-layout-front-Extra'),
    );
    await tester.ensureVisible(extraFrontToggle);
    await tester.pumpAndSettle();
    await tester.tap(extraFrontToggle);
    await tester.pump();
    final backRadio = find.byKey(const ValueKey('field-layout-radio-Back'));
    await tester.ensureVisible(backRadio);
    await tester.pumpAndSettle();
    await tester.tap(backRadio);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedResult, isNotNull);
    expect(savedResult!.orderedFields, ['Front', 'Extra', 'Back']);
    expect(savedResult!.frontField, 'Back');
    expect(savedResult!.frontFields, ['Front', 'Extra', 'Back']);
    expect(savedResult!.revealFields, ['Front', 'Extra', 'Back']);
  });

  testWidgets('explains cloze prompt and back ordering', (tester) async {
    final session = _session(
      fieldNames: const ['Text', 'Extra'],
      frontField: 'Text',
      cardType: SessionCardType.cloze,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FieldLayoutDialog(session: session)),
      ),
    );

    expect(find.text('Cloze prompt'), findsOneWidget);
    expect(find.textContaining('choose whether extra fields'), findsOneWidget);
  });
}

PreAnkiSession _session({
  required List<String> fieldNames,
  required String frontField,
  SessionCardType cardType = SessionCardType.questionAnswer,
}) {
  final now = DateTime(2026);
  return PreAnkiSession(
    id: 1,
    title: 'Session',
    source: 'test.csv',
    cardType: cardType,
    fieldNames: fieldNames,
    frontField: frontField,
    frontFields: [frontField],
    revealFields: [
      for (final field in fieldNames)
        if (field != frontField) field,
    ],
    exportFields: fieldNames,
    includeHeader: true,
    totalCards: 1,
    reviewIndex: 0,
    createdAt: now,
    updatedAt: now,
  );
}
