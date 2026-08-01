import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preanki/app_state.dart';
import 'package:preanki/design_system.dart';
import 'package:preanki/main.dart';
import 'package:preanki/models.dart';
import 'package:preanki/repository.dart';
import 'package:preanki/screens/session_screen.dart';
import 'package:preanki/widgets/html_card_text.dart';

void main() {
  testWidgets('review respects ordered front fields and back-only fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime(2026, 8, 1);
    final session = PreAnkiSession(
      id: 1,
      title: 'Focused review',
      source: 'test.csv',
      cardType: SessionCardType.cloze,
      fieldNames: const ['Context', 'Prompt', 'Answer', 'Extra'],
      frontField: 'Prompt',
      // The stored selection order is deliberately different. Display order
      // must always follow fieldNames, with Context before the cloze prompt.
      frontFields: const ['Prompt', 'Context'],
      revealFields: const ['Context', 'Answer', 'Extra'],
      exportFields: const ['Context', 'Prompt', 'Answer', 'Extra'],
      includeHeader: true,
      totalCards: 1,
      reviewIndex: 0,
      createdAt: now,
      updatedAt: now,
      reviewTotalCount: 1,
    );
    final card = Flashcard(
      id: 1,
      sessionId: 1,
      originalIndex: 0,
      fields: const {
        'Context': '<b>Context {{c2::hidden context}}</b>',
        'Prompt': 'What is {{c1::target}}?',
        'Answer': '<em>Back only answer</em>',
        'Extra': '<u>Extra</u> {{c2::revealed}}',
      },
      status: CardStatus.kept,
      createdAt: now,
      updatedAt: now,
    );
    final appState = _ReviewLayoutAppState(
      session: session,
      reviewCard: ReviewCard(
        card: card,
        clozeNumber: 1,
        reviewState: ReviewState.newCard,
      ),
    );

    await tester.pumpWidget(
      AppScope(
        appState: appState,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SessionScreen(sessionId: 1),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Learning queue'), findsNothing);
    expect(find.text('1 of 1'), findsOneWidget);
    expect(find.text('Show answer'), findsOneWidget);
    expect(find.text('Again'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Context'), findsOneWidget);
    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('Answer'), findsNothing);
    expect(_htmlValues(tester), ['<b>Context [ ... ]</b>', 'What is [ ... ]?']);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Smaller review text (85%)'));
    await tester.pump();
    expect(appState.reviewTextScale, 0.75);

    await tester.tap(find.text('Show answer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Show question'), findsOneWidget);
    expect(find.text('Context'), findsOneWidget);
    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('Answer'), findsOneWidget);
    expect(find.text('Extra'), findsOneWidget);
    final backWidgets = tester
        .widgetList<HtmlCardText>(find.byType(HtmlCardText))
        .toList();
    expect(backWidgets.map((widget) => widget.value).toList(), [
      allOf(contains('<b>Context'), contains('hidden context')),
      contains('target'),
      '<em>Back only answer</em>',
      allOf(contains('<u>Extra</u>'), contains('revealed')),
    ]);
    expect(backWidgets.every((widget) => widget.textScale == 0.75), isTrue);
    expect(backWidgets.any((widget) => widget.value.contains('{{')), isFalse);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();

    expect(find.text('Front'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Context'), findsNWidgets(2));
    expect(find.text('Prompt'), findsNWidgets(2));
    // Answer is configured as back-only, so its field label appears once.
    expect(find.text('Answer'), findsOneWidget);
    final previewWidgets = tester
        .widgetList<HtmlCardText>(find.byType(HtmlCardText))
        .toList();
    expect(previewWidgets, hasLength(6));
    expect(previewWidgets.map((widget) => widget.value).toList(), [
      '<b>Context [ ... ]</b>',
      'What is [ ... ]?',
      allOf(contains('<b>Context'), contains('hidden context')),
      contains('target'),
      '<em>Back only answer</em>',
      allOf(contains('<u>Extra</u>'), contains('revealed')),
    ]);
    expect(previewWidgets.every((widget) => widget.textScale == 0.75), isTrue);
    expect(
      previewWidgets.any((widget) => widget.value.contains('{{')),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}

List<String> _htmlValues(WidgetTester tester) {
  return tester
      .widgetList<HtmlCardText>(find.byType(HtmlCardText))
      .map((widget) => widget.value)
      .toList();
}

class _ReviewLayoutAppState extends PreAnkiAppState {
  _ReviewLayoutAppState({
    required PreAnkiSession session,
    required ReviewCard reviewCard,
  }) : super(repository: PreAnkiRepository()) {
    sessions = [session];
    currentSession = session;
    currentCards = [reviewCard.card];
    currentReviewItems = [reviewCard];
  }

  @override
  Future<void> openSession(int sessionId) async {}

  @override
  Future<void> setReviewTextScale(double value) async {
    reviewTextScale = value;
    notifyListeners();
  }
}
