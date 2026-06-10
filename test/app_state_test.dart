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

    expect(appState.nextReviewCard?.fields['Front'], 'A');
    expect(appState.reviewQueuePosition, 1);
    expect(appState.reviewQueueCount, 3);
    expect(appState.canMoveReviewBack, isFalse);
    expect(appState.canMoveReviewForward, isTrue);

    await appState.moveReviewPointer(1);
    expect(appState.nextReviewCard?.fields['Front'], 'B');
    expect(appState.reviewQueuePosition, 2);

    await appState.moveReviewPointer(-1);
    expect(appState.nextReviewCard?.fields['Front'], 'A');
    expect(appState.reviewQueuePosition, 1);

    expect(appState.currentCards.map((card) => card.reviewState).toSet(), {
      ReviewState.newCard,
    });
  });
}
