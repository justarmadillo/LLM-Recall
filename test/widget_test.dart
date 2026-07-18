import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('regular card editor shows cut copy and paste actions', (
    tester,
  ) async {
    String? clipboardText = 'Replacement text';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboardText};
        case 'Clipboard.hasStrings':
          return <String, bool>{
            'value': clipboardText != null && clipboardText!.isNotEmpty,
          };
        case 'Clipboard.setData':
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

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
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCardEditorDialog(
                context: context,
                card: card,
                fieldOrder: const ['Front', 'Back'],
              ),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final backFieldFinder = find.widgetWithText(TextField, 'Back');
    final backField = tester.widget<TextField>(backFieldFinder);
    expect(backField.contextMenuBuilder, isNotNull);

    await tester.tap(backFieldFinder);
    await tester.pump();
    backField.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    await tester.pump();

    final editableTextState = tester.state<EditableTextState>(
      find.descendant(of: backFieldFinder, matching: find.byType(EditableText)),
    );
    expect(editableTextState.showToolbar(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
  });

  testWidgets('add card dialog wraps selected cloze text', (tester) async {
    Map<String, String>? savedFields;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              savedFields = await showAddCardDialog(
                context: tester.element(find.text('Add card')),
                fieldOrder: const ['Text', 'Extra'],
                primaryField: 'Text',
                isClozeSession: true,
              );
            },
            child: const Text('Add card'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add card'));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, 'Text'),
      'The mitochondrion makes ATP',
    );
    final textField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Text'),
    );
    textField.controller!.selection = const TextSelection(
      baseOffset: 4,
      extentOffset: 17,
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Cloze selected text'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();

    expect(savedFields, isNotNull);
    expect(savedFields!['Text'], 'The {{c1::mitochondrion}} makes ATP');
  });
}
