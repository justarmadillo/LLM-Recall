import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preanki/app_state.dart';
import 'package:preanki/main.dart';
import 'package:preanki/repository.dart';
import 'package:preanki/screens/import_screen.dart';
import 'package:preanki/widgets/html_card_text.dart';

void main() {
  test('reorders row values with stable source-column indices', () {
    expect(
      reorderRowsBySourceIndices(
        const [
          ['Question', '<b>Answer</b>', 'Context'],
          ['Second', 'Response'],
        ],
        const [1, 0, 2],
      ),
      const [
        ['<b>Answer</b>', 'Question', 'Context'],
        ['Response', 'Second', ''],
      ],
    );
  });

  testWidgets('field mapping reorders HTML previews and prompt selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final appState = PreAnkiAppState(repository: PreAnkiRepository());
    await tester.pumpWidget(
      AppScope(
        appState: appState,
        child: const MaterialApp(
          home: ImportScreen(
            initialCsvText: 'Front,Back,Extra\nQuestion,<b>Answer</b>,Context',
            initialSourceName: 'ordered.csv',
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byType(ReorderableDragStartListener).evaluate().length == 3,
    );

    expect(find.byType(ReorderableDragStartListener), findsNWidgets(3));
    expect(
      tester.widget<RadioGroup<int>>(find.byType(RadioGroup<int>)).groupValue,
      0,
    );

    final reorderable = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    reorderable.onReorderItem!(1, 0);
    await tester.pump();

    expect(
      tester
          .widgetList<HtmlCardText>(find.byType(HtmlCardText))
          .map((widget) => widget.value),
      ['<b>Answer</b>', 'Question', 'Context'],
    );
    expect(
      tester.widget<RadioGroup<int>>(find.byType(RadioGroup<int>)).groupValue,
      0,
    );

    await tester.tap(find.byKey(const ValueKey<String>('import-primary-1')));
    await tester.pump();
    expect(
      tester.widget<RadioGroup<int>>(find.byType(RadioGroup<int>)).groupValue,
      1,
    );

    expect(find.text('Use as question prompt'), findsNWidgets(3));
    expect(find.text('Front & back (prompt)'), findsOneWidget);
    expect(find.text('Back only'), findsNWidgets(2));

    final extraFrontToggle = find.byKey(
      const ValueKey<String>('import-front-toggle-2'),
    );
    await tester.ensureVisible(extraFrontToggle);
    await tester.pumpAndSettle();
    await tester.tap(extraFrontToggle);
    await tester.pump();
    expect(tester.widget<Switch>(extraFrontToggle).value, isTrue);
    expect(find.text('Front & back'), findsOneWidget);
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 60 && !condition(); attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue);
}
