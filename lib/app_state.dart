// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'csv_tools.dart';
import 'export_service.dart';
import 'models.dart';
import 'repository.dart';

class PreAnkiAppState extends ChangeNotifier {
  // Keep public constructor labels instead of exposing private field names.
  PreAnkiAppState({
    required PreAnkiRepository repository,
    CsvTools? csvTools,
    ExportService? exportService,
  }) : _repository = repository,
       _csvTools = csvTools ?? CsvTools(),
       _exportService = exportService ?? ExportService(csvTools: csvTools);

  final PreAnkiRepository _repository;
  final CsvTools _csvTools;
  final ExportService _exportService;

  List<PreAnkiSession> sessions = const [];
  PreAnkiSession? currentSession;
  List<Flashcard> currentCards = const [];
  List<ReviewCard> currentReviewItems = const [];
  String? defaultExportFolder;
  String? errorMessage;
  bool isBusy = false;
  ReviewUndo? _lastUndo;

  ReviewCard? get nextReviewItem {
    final session = currentSession;
    if (session == null) {
      return null;
    }
    final learningItems = _reviewQueue;
    return learningItems.firstWhereOrNull(
          (item) => item.reviewKey >= session.reviewIndex,
        ) ??
        learningItems.firstOrNull;
  }

  bool get canUndoReview => _lastUndo != null;

  int get reviewQueueCount => _reviewQueue.length;

  int get reviewQueuePosition {
    final session = currentSession;
    final queue = _reviewQueue;
    if (session == null || queue.isEmpty) {
      return 0;
    }
    return _reviewQueueIndex(queue, session.reviewIndex) + 1;
  }

  bool get canMoveReviewBack => _canMoveReview(-1);

  bool get canMoveReviewForward => _canMoveReview(1);

  Future<void> load() async {
    await _run(() async {
      sessions = await _repository.listSessions();
      defaultExportFolder = await _repository.getSetting(
        _defaultExportFolderKey,
      );
    });
  }

  Future<void> openSession(int sessionId) async {
    await _run(() async {
      currentSession = await _repository.getSession(sessionId);
      currentCards = await _repository.listCards(sessionId);
      currentReviewItems = await _repository.listReviewCards(sessionId);
      _lastUndo = null;
    });
  }

  Future<int?> createSessionFromImport({
    required String title,
    required String source,
    SessionCardType cardType = SessionCardType.questionAnswer,
    required List<List<String>> rows,
    required List<String> fieldNames,
    required String frontField,
    required List<String> revealFields,
    required List<String> exportFields,
    required bool includeHeader,
  }) async {
    int? sessionId;
    await _run(() async {
      final cards = _csvTools.rowsToCards(rows: rows, fieldNames: fieldNames);
      sessionId = await _repository.createSession(
        title: title.trim().isEmpty ? 'Untitled session' : title.trim(),
        source: source,
        cardType: cardType,
        fieldNames: fieldNames,
        frontField: frontField,
        revealFields: revealFields,
        exportFields: exportFields,
        includeHeader: includeHeader,
        cardFields: cards,
      );
      sessions = await _repository.listSessions();
    });
    return sessionId;
  }

  Future<void> addCard(int sessionId, Map<String, String> fields) async {
    await _run(() async {
      await _repository.addCard(sessionId: sessionId, fields: fields);
      if (currentSession?.id == sessionId) {
        await _refreshCurrent(sessionId);
      } else {
        sessions = await _repository.listSessions();
      }
    });
  }

  Future<void> deleteSession(int sessionId) async {
    await _run(() async {
      await _repository.deleteSession(sessionId);
      if (currentSession?.id == sessionId) {
        currentSession = null;
        currentCards = const [];
        currentReviewItems = const [];
      }
      sessions = await _repository.listSessions();
    });
  }

  Future<void> renameSession(int sessionId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _run(() async {
      await _repository.updateSessionTitle(sessionId, trimmed);
      if (currentSession?.id == sessionId) {
        await _refreshCurrent(sessionId);
      } else {
        sessions = await _repository.listSessions();
      }
    });
  }

  Future<void> restartSession(int sessionId) async {
    await _run(() async {
      await _repository.restartSessionReview(sessionId);
      if (currentSession?.id == sessionId) {
        await _refreshCurrent(sessionId);
      } else {
        sessions = await _repository.listSessions();
      }
      _lastUndo = null;
    });
  }

  Future<void> learnedAndAdvance(ReviewCard item) async {
    await _reviewAdvance(item, reviewState: ReviewState.learned);
  }

  Future<void> againAndAdvance(ReviewCard item) async {
    await _reviewAdvance(item, reviewState: ReviewState.again);
  }

  Future<void> deleteAndAdvance(ReviewCard item) async {
    await _reviewAdvance(item, status: CardStatus.deleted);
  }

  Future<void> undoReviewAction() async {
    final undo = _lastUndo;
    if (undo == null) {
      return;
    }
    await _run(() async {
      await _repository.setCardStatus(undo.cardId, undo.previousStatus);
      await _repository.setReviewItemState(
        cardId: undo.cardId,
        clozeNumber: undo.clozeNumber,
        reviewState: undo.previousReviewState,
      );
      await _repository.updateReviewIndex(undo.sessionId, undo.previousIndex);
      await _refreshCurrent(undo.sessionId);
      _lastUndo = null;
    });
  }

  Future<void> moveReviewPointer(int delta) async {
    final session = currentSession;
    final sessionId = session?.id;
    final queue = _reviewQueue;
    if (session == null || sessionId == null || queue.isEmpty) {
      return;
    }
    final currentIndex = _reviewQueueIndex(queue, session.reviewIndex);
    final targetIndex = (currentIndex + delta)
        .clamp(0, queue.length - 1)
        .toInt();
    if (targetIndex == currentIndex) {
      return;
    }
    await _run(() async {
      await _repository.updateReviewIndex(
        sessionId,
        queue[targetIndex].reviewKey,
      );
      await _refreshCurrent(sessionId);
    });
  }

  Future<void> updateCard(Flashcard card, Map<String, String> fields) async {
    final cardId = card.id;
    if (cardId == null) {
      return;
    }
    await _run(() async {
      await _repository.updateCardFields(cardId, fields);
      await _refreshCurrent(card.sessionId);
    });
  }

  Future<void> setCardStatus(Flashcard card, CardStatus status) async {
    final cardId = card.id;
    if (cardId == null) {
      return;
    }
    await _run(() async {
      await _repository.setCardStatus(cardId, status);
      await _refreshCurrent(card.sessionId);
    });
  }

  Future<String?> exportSession(int sessionId) async {
    String? path;
    await _run(() async {
      final session = await _repository.getSession(sessionId);
      if (session == null) {
        throw StateError('Session not found.');
      }
      final keptCards = await _repository.listCards(
        sessionId,
        filter: CardFilter.kept,
      );
      path = await _exportService.saveSessionCsv(
        session: session,
        cards: keptCards,
        initialDirectory: defaultExportFolder,
      );
    });
    return path;
  }

  Future<void> setDefaultExportFolder(String? folder) async {
    await _run(() async {
      final value = folder?.trim();
      await _repository.setSetting(_defaultExportFolderKey, value);
      defaultExportFolder = value == null || value.isEmpty ? null : value;
    });
  }

  Future<String?> exportAppBackup() async {
    String? path;
    await _run(() async {
      final backup = await _repository.exportBackup();
      final json = const JsonEncoder.withIndent('  ').convert(backup);
      final bytes = Uint8List.fromList(utf8.encode(json));
      final timestamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final fileName = 'llm_recall_backup_$timestamp.json';
      final exportFolder = defaultExportFolder;
      String? pickerInitialDirectory;
      if (exportFolder != null && exportFolder.trim().isNotEmpty) {
        final directory = Directory(exportFolder);
        if (await directory.exists()) {
          pickerInitialDirectory = directory.path;
          try {
            final file = File(p.join(directory.path, fileName));
            await file.writeAsBytes(bytes);
            path = file.path;
            return;
          } on FileSystemException {
            // Fall through to the save picker if a remembered folder is stale.
          }
        }
      }
      final selectedPath = await FilePicker.saveFile(
        dialogTitle: 'Export LLM Recall backup',
        fileName: fileName,
        initialDirectory: pickerInitialDirectory,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Platform.isAndroid || Platform.isIOS ? bytes : null,
      );
      if (selectedPath == null) {
        return;
      }
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await File(selectedPath).writeAsBytes(bytes);
      }
      path = selectedPath;
    });
    return path;
  }

  Future<bool> importAppBackup() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return false;
    }

    var imported = false;
    await _run(() async {
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null && file.path == null) {
        throw const FileSystemException('Could not read backup file.');
      }
      final content = bytes != null
          ? utf8.decode(bytes)
          : await File(file.path!).readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const FormatException('Backup file must contain a JSON object.');
      }
      await _repository.importBackup(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      sessions = await _repository.listSessions();
      defaultExportFolder = await _repository.getSetting(
        _defaultExportFolderKey,
      );
      currentSession = null;
      currentCards = const [];
      currentReviewItems = const [];
      _lastUndo = null;
      imported = true;
    });
    return imported;
  }

  Future<void> _reviewAdvance(
    ReviewCard item, {
    CardStatus status = CardStatus.kept,
    ReviewState? reviewState,
  }) async {
    final session = currentSession;
    final card = item.card;
    final cardId = card.id;
    final sessionId = session?.id;
    if (session == null || cardId == null || sessionId == null) {
      return;
    }
    await _run(() async {
      _lastUndo = ReviewUndo(
        sessionId: sessionId,
        cardId: cardId,
        clozeNumber: item.clozeNumber,
        previousStatus: card.status,
        previousReviewState: item.reviewState,
        previousIndex: session.reviewIndex,
      );
      await _repository.setCardStatus(cardId, status);
      if (reviewState != null) {
        await _repository.setReviewItemState(
          cardId: cardId,
          clozeNumber: item.clozeNumber,
          reviewState: reviewState,
        );
      }
      await _repository.updateReviewIndex(sessionId, item.reviewKey + 1);
      await _refreshCurrent(sessionId);
    });
  }

  Future<void> _refreshCurrent(int sessionId) async {
    currentSession = await _repository.getSession(sessionId);
    currentCards = await _repository.listCards(sessionId);
    currentReviewItems = await _repository.listReviewCards(sessionId);
    sessions = await _repository.listSessions();
  }

  List<ReviewCard> get _reviewQueue {
    return currentReviewItems
        .where(
          (item) =>
              item.card.status == CardStatus.kept &&
              item.reviewState != ReviewState.learned,
        )
        .toList();
  }

  bool _canMoveReview(int delta) {
    final session = currentSession;
    final queue = _reviewQueue;
    if (session == null || queue.isEmpty) {
      return false;
    }
    final currentIndex = _reviewQueueIndex(queue, session.reviewIndex);
    final targetIndex = currentIndex + delta;
    return targetIndex >= 0 && targetIndex < queue.length;
  }

  int _reviewQueueIndex(List<ReviewCard> queue, int reviewIndex) {
    final index = queue.indexWhere((item) => item.reviewKey >= reviewIndex);
    return index == -1 ? 0 : index;
  }

  Future<void> _run(Future<void> Function() action) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}

const _defaultExportFolderKey = 'default_export_folder';

class ReviewUndo {
  const ReviewUndo({
    required this.sessionId,
    required this.cardId,
    required this.clozeNumber,
    required this.previousStatus,
    required this.previousReviewState,
    required this.previousIndex,
  });

  final int sessionId;
  final int cardId;
  final int clozeNumber;
  final CardStatus previousStatus;
  final ReviewState previousReviewState;
  final int previousIndex;
}
