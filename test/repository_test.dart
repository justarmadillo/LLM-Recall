import 'package:flutter_test/flutter_test.dart';
import 'package:preanki/models.dart';
import 'package:preanki/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late PreAnkiRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    repository = PreAnkiRepository(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await repository.initialize();
  });

  tearDown(() => repository.close());

  test(
    'persists sessions, cards, edits, deletes, and review progress',
    () async {
      final sessionId = await repository.createSession(
        title: 'Biology review',
        source: 'test.csv',
        fieldNames: const ['Front', 'Back'],
        frontField: 'Front',
        revealFields: const ['Back'],
        exportFields: const ['Front', 'Back'],
        includeHeader: true,
        cardFields: const [
          {'Front': 'Cell powerhouse', 'Back': 'Mitochondria'},
          {'Front': 'DNA bases', 'Back': 'A C G T'},
          {'Front': 'Protein builder', 'Back': 'Ribosome'},
        ],
      );

      var session = await repository.getSession(sessionId);
      expect(session, isNotNull);
      expect(session!.totalCards, 3);

      var cards = await repository.listCards(sessionId);
      expect(cards, hasLength(3));
      expect(cards.first.reviewState, ReviewState.newCard);

      await repository.updateCardFields(cards.first.id!, {
        'Front': 'Powerhouse of the cell',
        'Back': 'Mitochondria',
      });
      await repository.setCardReviewState(cards.first.id!, ReviewState.learned);
      await repository.setCardStatus(cards[1].id!, CardStatus.deleted);
      await repository.setCardReviewState(cards.last.id!, ReviewState.again);
      await repository.updateReviewIndex(sessionId, 1);

      session = await repository.getSession(sessionId);
      cards = await repository.listCards(sessionId);
      final learning = await repository.listCards(
        sessionId,
        filter: CardFilter.learning,
      );
      final learned = await repository.listCards(
        sessionId,
        filter: CardFilter.learned,
      );
      final deleted = await repository.listCards(
        sessionId,
        filter: CardFilter.deleted,
      );

      expect(session!.reviewIndex, 1);
      expect(session.deletedCount, 1);
      expect(session.learnedCount, 1);
      expect(session.againCount, 1);
      expect(session.learningCount, 1);
      expect(cards.first.fields['Front'], 'Powerhouse of the cell');
      expect(learning.single.fields['Front'], 'Protein builder');
      expect(learned.single.fields['Front'], 'Powerhouse of the cell');
      expect(deleted.single.fields['Front'], 'DNA bases');

      await repository.updateSessionTitle(sessionId, 'Cell biology');
      await repository.setSetting('default_export_folder', 'D:\\Exports');
      expect(
        await repository.getSetting('default_export_folder'),
        'D:\\Exports',
      );

      await repository.restartSessionReview(sessionId);
      session = await repository.getSession(sessionId);
      final restartedLearning = await repository.listCards(
        sessionId,
        filter: CardFilter.learning,
      );
      final restartedLearned = await repository.listCards(
        sessionId,
        filter: CardFilter.learned,
      );

      expect(session!.title, 'Cell biology');
      expect(session.reviewIndex, 0);
      expect(session.learnedCount, 0);
      expect(restartedLearning, hasLength(2));
      expect(restartedLearned, isEmpty);
    },
  );

  test('exports and imports a complete app backup', () async {
    final sessionId = await repository.createSession(
      title: 'History',
      source: 'history.csv',
      cardType: SessionCardType.cloze,
      fieldNames: const ['Front', 'Back'],
      frontField: 'Front',
      revealFields: const ['Back'],
      exportFields: const ['Front', 'Back'],
      includeHeader: true,
      cardFields: const [
        {'Front': 'Magna Carta', 'Back': '<b>1215</b>'},
      ],
    );
    final cards = await repository.listCards(sessionId);
    await repository.setCardReviewState(cards.single.id!, ReviewState.learned);
    await repository.setSetting('default_export_folder', 'D:\\Recall');

    final backup = await repository.exportBackup();
    final restored = PreAnkiRepository(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await restored.initialize();
    addTearDown(restored.close);

    await restored.importBackup(backup);
    final restoredSessions = await restored.listSessions();
    final restoredCards = await restored.listCards(restoredSessions.single.id!);

    expect(restoredSessions.single.title, 'History');
    expect(restoredSessions.single.cardType, SessionCardType.cloze);
    expect(restoredSessions.single.learnedCount, 1);
    expect(restoredCards.single.fields['Back'], '<b>1215</b>');
    expect(await restored.getSetting('default_export_folder'), 'D:\\Recall');
  });

  test('adds a card at the end of an existing session', () async {
    final sessionId = await repository.createSession(
      title: 'Additions',
      source: 'manual',
      fieldNames: const ['Front', 'Back'],
      frontField: 'Front',
      revealFields: const ['Back'],
      exportFields: const ['Front', 'Back'],
      includeHeader: true,
      cardFields: const [
        {'Front': 'First', 'Back': 'One'},
      ],
    );

    final addedId = await repository.addCard(
      sessionId: sessionId,
      fields: const {'Front': 'Second', 'Back': 'Two'},
    );
    final session = await repository.getSession(sessionId);
    final cards = await repository.listCards(sessionId);

    expect(addedId, isPositive);
    expect(session!.totalCards, 2);
    expect(cards.last.originalIndex, 1);
    expect(cards.last.reviewState, ReviewState.newCard);
    expect(cards.last.fields['Front'], 'Second');
  });

  test('expands cloze notes into separate persisted review items', () async {
    final sessionId = await repository.createSession(
      title: 'Cloze expansion',
      source: 'cloze.csv',
      cardType: SessionCardType.cloze,
      fieldNames: const ['Text', 'Extra'],
      frontField: 'Text',
      revealFields: const ['Extra'],
      exportFields: const ['Text', 'Extra'],
      includeHeader: true,
      cardFields: const [
        {
          'Text':
              '{{c1::Mitochondria}} make {{c2::ATP}} and {{c1::ribosomes}} make proteins.',
          'Extra': 'Cell biology',
        },
      ],
    );

    var session = await repository.getSession(sessionId);
    var reviewItems = await repository.listReviewCards(sessionId);
    var cards = await repository.listCards(sessionId);

    expect(session!.totalCards, 1);
    expect(session.reviewCount, 2);
    expect(reviewItems.map((item) => item.clozeNumber), [1, 2]);
    expect(cards.single.reviewState, ReviewState.newCard);

    await repository.setReviewItemState(
      cardId: cards.single.id!,
      clozeNumber: 1,
      reviewState: ReviewState.learned,
    );

    session = await repository.getSession(sessionId);
    reviewItems = await repository.listReviewCards(sessionId);
    cards = await repository.listCards(sessionId);

    expect(session!.learnedCount, 1);
    expect(session.learningCount, 1);
    expect(reviewItems.first.reviewState, ReviewState.learned);
    expect(cards.single.reviewState, ReviewState.newCard);

    await repository.setReviewItemState(
      cardId: cards.single.id!,
      clozeNumber: 2,
      reviewState: ReviewState.learned,
    );

    session = await repository.getSession(sessionId);
    cards = await repository.listCards(sessionId);

    expect(session!.learnedCount, 2);
    expect(session.progress, 1);
    expect(cards.single.reviewState, ReviewState.learned);
  });

  test('rejects malformed backups before replacing existing data', () async {
    final sessionId = await repository.createSession(
      title: 'Keep me',
      source: 'safe.csv',
      fieldNames: const ['Front', 'Back'],
      frontField: 'Front',
      revealFields: const ['Back'],
      exportFields: const ['Front', 'Back'],
      includeHeader: true,
      cardFields: const [
        {'Front': 'Still here?', 'Back': 'Yes'},
      ],
    );

    await expectLater(
      repository.importBackup({
        'format': 'llm_recall_backup',
        'formatVersion': 1,
        'sessions': 'not a list',
      }),
      throwsFormatException,
    );

    final sessions = await repository.listSessions();
    final cards = await repository.listCards(sessionId);

    expect(sessions.single.title, 'Keep me');
    expect(cards.single.fields['Back'], 'Yes');
  });

  test('rejects backups from a newer backup format', () async {
    await expectLater(
      repository.importBackup({
        'format': 'llm_recall_backup',
        'formatVersion': 2,
        'sessions': const [],
      }),
      throwsFormatException,
    );
  });
}
