import 'dart:io';

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
      frontFields: const ['Back', 'Front'],
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
    expect(backup['formatVersion'], 2);
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
    expect(restoredSessions.single.frontFields, ['Front', 'Back']);
    expect(restoredSessions.single.learnedCount, 1);
    expect(restoredCards.single.fields['Back'], '<b>1215</b>');
    expect(await restored.getSetting('default_export_folder'), 'D:\\Recall');
  });

  test(
    'imports version 1 backups with the prompt as the sole front field',
    () async {
      final sessionId = await repository.createSession(
        title: 'Legacy backup',
        source: 'legacy.csv',
        fieldNames: const ['Context', 'Prompt', 'Answer'],
        frontField: 'Prompt',
        frontFields: const ['Context', 'Prompt'],
        revealFields: const ['Answer'],
        exportFields: const ['Context', 'Prompt', 'Answer'],
        includeHeader: true,
        cardFields: const [
          {'Context': 'Chapter 1', 'Prompt': 'Question', 'Answer': 'Answer'},
        ],
      );
      expect(sessionId, isPositive);

      final currentBackup = await repository.exportBackup();
      final legacySessions = <Map<String, Object?>>[];
      for (final rawEntry in currentBackup['sessions']! as List) {
        final entry = Map<String, Object?>.from(rawEntry as Map);
        final session = Map<String, Object?>.from(entry['session']! as Map)
          ..remove('front_fields');
        legacySessions.add({...entry, 'session': session});
      }
      final legacyBackup = <String, Object?>{
        ...currentBackup,
        'formatVersion': 1,
        'databaseVersion': 7,
        'sessions': legacySessions,
      };

      final restored = PreAnkiRepository(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      await restored.initialize();
      addTearDown(restored.close);
      await restored.importBackup(legacyBackup);

      final session = (await restored.listSessions()).single;
      expect(session.frontField, 'Prompt');
      expect(session.frontFields, ['Prompt']);
      expect(session.revealFields, ['Context', 'Prompt', 'Answer']);
      expect(session.exportFields, ['Context', 'Prompt', 'Answer']);
    },
  );

  test('migrates schema 7 sessions to a sole persisted front field', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'memory_studio_schema_',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final databasePath =
        '${temporaryDirectory.path}${Platform.pathSeparator}legacy.db';
    final legacyDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              source TEXT NOT NULL,
              card_type TEXT NOT NULL DEFAULT 'question_answer',
              field_names TEXT NOT NULL,
              front_field TEXT NOT NULL,
              reveal_fields TEXT NOT NULL,
              export_fields TEXT NOT NULL,
              include_header INTEGER NOT NULL,
              total_cards INTEGER NOT NULL,
              review_index INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE cards (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id INTEGER NOT NULL,
              original_index INTEGER NOT NULL,
              fields_json TEXT NOT NULL,
              status TEXT NOT NULL,
              review_state TEXT NOT NULL DEFAULT 'new',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE card_review_items (
              card_id INTEGER NOT NULL,
              cloze_number INTEGER NOT NULL,
              review_state TEXT NOT NULL DEFAULT 'new',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              PRIMARY KEY(card_id, cloze_number)
            )
          ''');
          await database.insert('sessions', {
            'title': 'Migrated session',
            'source': 'legacy.csv',
            'card_type': 'cloze',
            'field_names': '["Context","Text"]',
            'front_field': 'Text',
            'reveal_fields': '["Context"]',
            'export_fields': '["Context","Text"]',
            'include_header': 1,
            'total_cards': 0,
            'review_index': 0,
            'created_at': '2026-01-01T00:00:00.000',
            'updated_at': '2026-01-01T00:00:00.000',
          });
        },
      ),
    );
    await legacyDatabase.close();

    final migrated = PreAnkiRepository(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await migrated.initialize();
    addTearDown(migrated.close);

    final session = (await migrated.listSessions()).single;
    expect(session.frontField, 'Text');
    expect(session.frontFields, ['Text']);
    expect(session.revealFields, ['Context', 'Text']);
  });

  test('rejects front fields that do not include the prompt field', () async {
    await expectLater(
      repository.createSession(
        title: 'Invalid front fields',
        source: 'test.csv',
        fieldNames: const ['Prompt', 'Context'],
        frontField: 'Prompt',
        frontFields: const ['Context'],
        revealFields: const ['Context'],
        exportFields: const ['Prompt', 'Context'],
        includeHeader: true,
        cardFields: const [],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('must include the prompt field'),
        ),
      ),
    );
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

  test(
    'reorders fields without migrating cloze review state or export order',
    () async {
      final sessionId = await repository.createSession(
        title: 'Reordered cloze fields',
        source: 'cloze.csv',
        cardType: SessionCardType.cloze,
        fieldNames: const ['Text', 'Extra', 'Source'],
        frontField: 'Text',
        revealFields: const ['Extra', 'Source'],
        exportFields: const ['Text', 'Extra', 'Source'],
        includeHeader: true,
        cardFields: const [
          {
            'Text': '{{c1::Mitochondria}} make ATP.',
            'Extra': 'Cell biology',
            'Source': 'Chapter 1',
          },
        ],
      );
      final card = (await repository.listCards(sessionId)).single;
      await repository.setReviewItemState(
        cardId: card.id!,
        clozeNumber: 1,
        reviewState: ReviewState.learned,
      );
      await repository.updateReviewIndex(sessionId, 1234567);

      await repository.updateSessionFieldLayout(
        sessionId: sessionId,
        fieldNames: const ['Source', 'Text', 'Extra'],
        frontField: 'Text',
        frontFields: const ['Text', 'Source'],
      );

      final session = await repository.getSession(sessionId);
      final reviewItems = await repository.listReviewCards(sessionId);

      expect(session!.fieldNames, ['Source', 'Text', 'Extra']);
      expect(session.frontField, 'Text');
      expect(session.frontFields, ['Source', 'Text']);
      expect(session.revealFields, ['Source', 'Text', 'Extra']);
      expect(session.exportFields, ['Text', 'Extra', 'Source']);
      expect(session.reviewIndex, 1234567);
      expect(reviewItems.single.clozeNumber, 1);
      expect(reviewItems.single.reviewState, ReviewState.learned);
    },
  );

  test('migrates review items when the cloze prompt field changes', () async {
    final sessionId = await repository.createSession(
      title: 'Switch cloze field',
      source: 'cloze.csv',
      cardType: SessionCardType.cloze,
      fieldNames: const ['Old', 'New', 'Extra'],
      frontField: 'Old',
      revealFields: const ['New', 'Extra'],
      exportFields: const ['Old', 'New', 'Extra'],
      includeHeader: true,
      cardFields: const [
        {'Old': '{{c1::Old A}}', 'New': '{{c2::New A}}', 'Extra': 'A'},
        {'Old': '{{c1::Old B}}', 'New': '{{c1::New B}}', 'Extra': 'B'},
      ],
    );
    final cards = await repository.listCards(sessionId);
    await repository.setReviewItemState(
      cardId: cards.first.id!,
      clozeNumber: 1,
      reviewState: ReviewState.learned,
    );
    await repository.setReviewItemState(
      cardId: cards.last.id!,
      clozeNumber: 1,
      reviewState: ReviewState.again,
    );
    await repository.updateReviewIndex(sessionId, 2000001);

    await repository.updateSessionFieldLayout(
      sessionId: sessionId,
      fieldNames: const ['Extra', 'New', 'Old'],
      frontField: 'New',
      frontFields: const ['New', 'Extra'],
    );

    final session = await repository.getSession(sessionId);
    final migratedItems = await repository.listReviewCards(sessionId);
    final migratedCards = await repository.listCards(sessionId);

    expect(session!.fieldNames, ['Extra', 'New', 'Old']);
    expect(session.frontField, 'New');
    expect(session.frontFields, ['Extra', 'New']);
    expect(session.revealFields, ['Extra', 'New', 'Old']);
    expect(session.exportFields, ['Old', 'New', 'Extra']);
    expect(session.reviewIndex, 0);
    expect(migratedItems.map((item) => item.clozeNumber), [2, 1]);
    expect(migratedItems.map((item) => item.reviewState), [
      ReviewState.newCard,
      ReviewState.again,
    ]);
    expect(migratedCards.map((card) => card.reviewState), [
      ReviewState.newCard,
      ReviewState.again,
    ]);
  });

  test(
    'rejects an invalid cloze prompt field without partial changes',
    () async {
      final sessionId = await repository.createSession(
        title: 'Invalid switch',
        source: 'cloze.csv',
        cardType: SessionCardType.cloze,
        fieldNames: const ['Old', 'Candidate'],
        frontField: 'Old',
        revealFields: const ['Candidate'],
        exportFields: const ['Old', 'Candidate'],
        includeHeader: true,
        cardFields: const [
          {'Old': '{{c1::Old A}}', 'Candidate': '{{c2::New A}}'},
          {'Old': '{{c1::Old B}}', 'Candidate': 'No deletion here'},
        ],
      );
      final cards = await repository.listCards(sessionId);
      await repository.setReviewItemState(
        cardId: cards.first.id!,
        clozeNumber: 1,
        reviewState: ReviewState.learned,
      );
      await repository.updateReviewIndex(sessionId, 1000001);

      await expectLater(
        repository.updateSessionFieldLayout(
          sessionId: sessionId,
          fieldNames: const ['Candidate', 'Old'],
          frontField: 'Candidate',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('card 2 has no cloze deletion'),
          ),
        ),
      );

      final session = await repository.getSession(sessionId);
      final reviewItems = await repository.listReviewCards(sessionId);

      expect(session!.fieldNames, ['Old', 'Candidate']);
      expect(session.frontField, 'Old');
      expect(session.revealFields, ['Old', 'Candidate']);
      expect(session.reviewIndex, 1000001);
      expect(reviewItems.map((item) => item.clozeNumber), [1, 1]);
      expect(reviewItems.map((item) => item.reviewState), [
        ReviewState.learned,
        ReviewState.newCard,
      ]);
    },
  );

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
        'formatVersion': 3,
        'sessions': const [],
      }),
      throwsFormatException,
    );
  });
}
