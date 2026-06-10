import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preanki/models.dart';
import 'package:preanki/widgets/card_editor_dialog.dart';

void main() {
  testWidgets('card editor returns edited mapped fields', (tester) async {
    Map<String, String>? savedFields;
    final card = Flashcard(
      id: 1,
      sessionId: 1,
      originalIndex: 0,
      fields: const {'Front': 'Capital?', 'Back': 'Paris'},
      status: CardStatus.kept,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              savedFields = await showCardEditorDialog(
                context: tester.element(find.text('Edit')),
                card: card,
                fieldOrder: const ['Front', 'Back'],
              );
            },
            child: const Text('Edit'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit'));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, 'Back'),
      'Paris, France',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(savedFields, isNotNull);
    expect(savedFields!['Front'], 'Capital?');
    expect(savedFields!['Back'], 'Paris, France');
  });
}
