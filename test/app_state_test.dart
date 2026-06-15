import 'package:flutter_test/flutter_test.dart';
import 'package:preanki/app_state.dart';
import 'package:preanki/models.dart';
import 'package:preanki/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late PreAnkiRepository repository;
  late PreAnkiAppState appState;

  setUp(() async {
    sqfliteFfiInit();
    repository = PreAnkiRepository(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await repository.initialize();
    appState = PreAnkiAppState(repository: repository);
  });

  tearDown(() => repository.close());

  test('moves through review cards without grading them', () async {
    final sessionId = await appState.createSessionFromImport(
      title: 'Linking review',
      source: 'test.csv',
      rows: const [
        ['A', 'one'],
        ['B', 'two'],
        ['C', 'three'],
      ],
      fieldNames: const ['Front', 'Back'],
      frontField: 'Front',
      revealFields: const ['Back'],
      exportFields: const ['Front', 'Back'],
      includeHeader: true,
    );
    await appState.openSession(sessionId!);

    expect(appState.nextReviewItem?.card.fields['Front'], 'A');
    expect(appState.reviewQueuePosition, 1);
    expect(appState.reviewQueueCount, 3);
    expect(appState.canMoveReviewBack, isFalse);
    expect(appState.canMoveReviewForward, isTrue);

    await appState.moveReviewPointer(1);
    expect(appState.nextReviewItem?.card.fields['Front'], 'B');
    expect(appState.reviewQueuePosition, 2);

    await appState.moveReviewPointer(-1);
    expect(appState.nextReviewItem?.card.fields['Front'], 'A');
    expect(appState.reviewQueuePosition, 1);

    expect(appState.currentCards.map((card) => card.reviewState).toSet(), {
      ReviewState.newCard,
    });
  });

  test('adds cards and refreshes the open session', () async {
    final sessionId = await appState.createSessionFromImport(
      title: 'Manual additions',
      source: 'test.csv',
      rows: const [
        ['A', 'one'],
      ],
      fieldNames: const ['Front', 'Back'],
      frontField: 'Front',
      revealFields: const ['Back'],
      exportFields: const ['Front', 'Back'],
      includeHeader: true,
    );
    await appState.openSession(sessionId!);

    await appState.addCard(sessionId, const {'Front': 'B', 'Back': 'two'});

    expect(appState.currentSession!.totalCards, 2);
    expect(appState.currentCards.map((card) => card.fields['Front']), [
      'A',
      'B',
    ]);
    expect(appState.sessions.single.totalCards, 2);
  });

  test('reviews each distinct cloze number from one stored note', () async {
    final sessionId = await appState.createSessionFromImport(
      title: 'Cloze review',
      source: 'cloze.csv',
      cardType: SessionCardType.cloze,
      rows: const [
        [
          '{{c1::Mitochondria}} make {{c2::ATP}} and {{c1::ribosomes}} make proteins.',
          'Cell biology',
        ],
      ],
      fieldNames: const ['Text', 'Extra'],
      frontField: 'Text',
      revealFields: const ['Extra'],
      exportFields: const ['Text', 'Extra'],
      includeHeader: true,
    );
    await appState.openSession(sessionId!);

    expect(appState.currentSession!.totalCards, 1);
    expect(appState.currentSession!.reviewCount, 2);
    expect(appState.reviewQueueCount, 2);
    expect(appState.nextReviewItem!.clozeNumber, 1);

    await appState.learnedAndAdvance(appState.nextReviewItem!);

    expect(appState.nextReviewItem!.clozeNumber, 2);
    expect(appState.currentSession!.learnedCount, 1);
    expect(appState.currentSession!.learningCount, 1);
    expect(appState.currentCards.single.reviewState, ReviewState.newCard);

    await appState.learnedAndAdvance(appState.nextReviewItem!);

    expect(appState.nextReviewItem, isNull);
    expect(appState.currentSession!.learnedCount, 2);
    expect(appState.currentSession!.progress, 1);
    expect(appState.currentCards.single.reviewState, ReviewState.learned);
  });
}
