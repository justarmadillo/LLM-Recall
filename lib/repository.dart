// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models.dart';

class PreAnkiRepository {
  // Keep public constructor labels instead of exposing private field names.
  PreAnkiRepository({
    DatabaseFactory? databaseFactoryOverride,
    String? databasePath,
  }) : _databaseFactoryOverride = databaseFactoryOverride,
       _databasePath = databasePath;

  final DatabaseFactory? _databaseFactoryOverride;
  final String? _databasePath;
  Database? _database;

  Future<void> initialize() async {
    _database = await _openDatabase();
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<List<PreAnkiSession>> listSessions() async {
    final rows = await _db.query('sessions', orderBy: 'updated_at DESC');
    final sessions = <PreAnkiSession>[];
    for (final row in rows) {
      final sessionId = row['id'] as int;
      sessions.add(
        PreAnkiSession.fromDb(
          row,
          deletedCount: await _deletedCount(sessionId),
          learnedCount: await _reviewStateCount(sessionId, ReviewState.learned),
          againCount: await _reviewStateCount(sessionId, ReviewState.again),
        ),
      );
    }
    return sessions;
  }

  Future<PreAnkiSession?> getSession(int id) async {
    final rows = await _db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PreAnkiSession.fromDb(
      rows.single,
      deletedCount: await _deletedCount(id),
      learnedCount: await _reviewStateCount(id, ReviewState.learned),
      againCount: await _reviewStateCount(id, ReviewState.again),
    );
  }

  Future<int> createSession({
    required String title,
    required String source,
    required List<String> fieldNames,
    required String frontField,
    required List<String> revealFields,
    required List<String> exportFields,
    required bool includeHeader,
    required List<Map<String, String>> cardFields,
  }) async {
    final now = DateTime.now();
    return _db.transaction((txn) async {
      final sessionId = await txn.insert('sessions', {
        'title': title,
        'source': source,
        'field_names': _encodeList(fieldNames),
        'front_field': frontField,
        'reveal_fields': _encodeList(revealFields),
        'export_fields': _encodeList(exportFields),
        'include_header': includeHeader ? 1 : 0,
        'total_cards': cardFields.length,
        'review_index': 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      for (var index = 0; index < cardFields.length; index += 1) {
        await txn.insert('cards', {
          'session_id': sessionId,
          'original_index': index,
          'fields_json': _encodeMap(cardFields[index]),
          'status': CardStatus.kept.name,
          'review_state': ReviewState.newCard.storageValue,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }
      return sessionId;
    });
  }

  Future<void> deleteSession(int id) async {
    await _db.transaction((txn) async {
      await txn.delete('cards', where: 'session_id = ?', whereArgs: [id]);
      await txn.delete('sessions', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> updateSessionTitle(int sessionId, String title) async {
    final now = DateTime.now().toIso8601String();
    await _db.update(
      'sessions',
      {'title': title, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> restartSessionReview(int sessionId) async {
    final now = DateTime.now().toIso8601String();
    await _db.transaction((txn) async {
      await txn.update(
        'cards',
        {'review_state': ReviewState.newCard.storageValue, 'updated_at': now},
        where: 'session_id = ? AND status = ?',
        whereArgs: [sessionId, CardStatus.kept.name],
      );
      await txn.update(
        'sessions',
        {'review_index': 0, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  Future<List<Flashcard>> listCards(
    int sessionId, {
    CardFilter filter = CardFilter.all,
  }) async {
    final where = switch (filter) {
      CardFilter.all => 'session_id = ?',
      CardFilter.kept => 'session_id = ? AND status = ?',
      CardFilter.learning =>
        'session_id = ? AND status = ? AND review_state != ?',
      CardFilter.learned =>
        'session_id = ? AND status = ? AND review_state = ?',
      CardFilter.deleted => 'session_id = ? AND status = ?',
    };
    final whereArgs = switch (filter) {
      CardFilter.all => [sessionId],
      CardFilter.kept => [sessionId, CardStatus.kept.name],
      CardFilter.learning => [
        sessionId,
        CardStatus.kept.name,
        ReviewState.learned.storageValue,
      ],
      CardFilter.learned => [
        sessionId,
        CardStatus.kept.name,
        ReviewState.learned.storageValue,
      ],
      CardFilter.deleted => [sessionId, CardStatus.deleted.name],
    };
    final rows = await _db.query(
      'cards',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'original_index ASC',
    );
    return rows.map(Flashcard.fromDb).toList();
  }

  Future<Flashcard?> getCard(int id) async {
    final rows = await _db.query(
      'cards',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Flashcard.fromDb(rows.single);
  }

  Future<void> updateCardFields(int cardId, Map<String, String> fields) async {
    final now = DateTime.now().toIso8601String();
    final card = await getCard(cardId);
    if (card == null) {
      return;
    }
    await _db.transaction((txn) async {
      await txn.update(
        'cards',
        {'fields_json': _encodeMap(fields), 'updated_at': now},
        where: 'id = ?',
        whereArgs: [cardId],
      );
      await _touchSession(txn, card.sessionId, now);
    });
  }

  Future<void> setCardStatus(int cardId, CardStatus status) async {
    final now = DateTime.now().toIso8601String();
    final card = await getCard(cardId);
    if (card == null) {
      return;
    }
    await _db.transaction((txn) async {
      await txn.update(
        'cards',
        {'status': status.name, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [cardId],
      );
      await _touchSession(txn, card.sessionId, now);
    });
  }

  Future<void> setCardReviewState(int cardId, ReviewState reviewState) async {
    final now = DateTime.now().toIso8601String();
    final card = await getCard(cardId);
    if (card == null) {
      return;
    }
    await _db.transaction((txn) async {
      await txn.update(
        'cards',
        {'review_state': reviewState.storageValue, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [cardId],
      );
      await _touchSession(txn, card.sessionId, now);
    });
  }

  Future<void> updateReviewIndex(int sessionId, int reviewIndex) async {
    final now = DateTime.now().toIso8601String();
    await _db.update(
      'sessions',
      {'review_index': reviewIndex, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<Map<String, Object?>> exportBackup() async {
    final sessionRows = await _db.query('sessions', orderBy: 'id ASC');
    final sessionsWithCards = <Map<String, Object?>>[];
    for (final session in sessionRows) {
      final sessionId = session['id'] as int;
      final cleanSession = Map<String, Object?>.from(session)
        ..remove('preset_id');
      sessionsWithCards.add({
        'session': cleanSession,
        'cards': await _db.query(
          'cards',
          where: 'session_id = ?',
          whereArgs: [sessionId],
          orderBy: 'original_index ASC',
        ),
      });
    }
    final settingsRows = await _db.query('app_settings', orderBy: 'key ASC');
    return {
      'format': 'llm_recall_backup',
      'formatVersion': 1,
      'databaseVersion': 5,
      'exportedAt': DateTime.now().toIso8601String(),
      'sessions': sessionsWithCards,
      'settings': settingsRows,
    };
  }

  Future<void> importBackup(Map<String, Object?> backup) async {
    if (backup['format'] != 'llm_recall_backup') {
      throw const FormatException('This is not an LLM Recall backup file.');
    }
    final formatVersion = _backupInt(backup['formatVersion']) ?? 1;
    if (formatVersion > 1) {
      throw FormatException(
        'This backup was created by a newer LLM Recall backup format ($formatVersion).',
      );
    }
    final sessions = _requiredBackupList(backup, 'sessions');
    final settings = _backupList(backup['settings']);

    await _db.transaction((txn) async {
      await txn.delete('cards');
      await txn.delete('sessions');
      await txn.delete('app_settings');

      for (final entry in sessions) {
        final session = _backupMap(entry['session']);
        final cards = _backupList(entry['cards']);
        await txn.insert('sessions', _sqliteRow(session)..remove('preset_id'));
        for (final card in cards) {
          await txn.insert('cards', _sqliteRow(card));
        }
      }
      for (final setting in settings) {
        await txn.insert('app_settings', _sqliteRow(setting));
      }
    });
  }

  Future<String?> getSetting(String key) async {
    final rows = await _db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await _db.insert('app_settings', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Database> _openDatabase() async {
    final factory = _databaseFactoryOverride ?? _databaseFactoryForPlatform();
    final path = _databasePath ?? await _defaultDatabasePath();
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              source TEXT NOT NULL,
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
          await db.execute('''
            CREATE TABLE cards (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id INTEGER NOT NULL,
              original_index INTEGER NOT NULL,
              fields_json TEXT NOT NULL,
              status TEXT NOT NULL,
              review_state TEXT NOT NULL DEFAULT 'new',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY(session_id) REFERENCES sessions(id)
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_cards_session ON cards(session_id, original_index)',
          );
          await db.execute('''
            CREATE TABLE app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE cards ADD COLUMN review_state TEXT NOT NULL DEFAULT 'new'",
            );
          }
          if (oldVersion < 3) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
          }
          if (oldVersion < 5) {
            await db.execute('DROP TABLE IF EXISTS presets');
          }
        },
      ),
    );
  }

  DatabaseFactory _databaseFactoryForPlatform() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return databaseFactory;
  }

  Future<String> _defaultDatabasePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, 'preanki.db');
  }

  Future<int> _deletedCount(int sessionId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM cards WHERE session_id = ? AND status = ?',
      [sessionId, CardStatus.deleted.name],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> _reviewStateCount(int sessionId, ReviewState reviewState) async {
    final result = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM cards
      WHERE session_id = ? AND status = ? AND review_state = ?
      ''',
      [sessionId, CardStatus.kept.name, reviewState.storageValue],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> _touchSession(Transaction txn, int sessionId, String now) {
    return txn.update(
      'sessions',
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Database get _db {
    final database = _database;
    if (database == null) {
      throw StateError('PreAnkiRepository.initialize() must be called first.');
    }
    return database;
  }
}

String _encodeList(List<String> values) {
  return jsonEncode(values);
}

String _encodeMap(Map<String, String> values) {
  return jsonEncode(values);
}

List<Map<String, Object?>> _backupList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map(_backupMap).toList();
}

List<Map<String, Object?>> _requiredBackupList(
  Map<String, Object?> backup,
  String key,
) {
  if (!backup.containsKey(key)) {
    throw FormatException('Backup file is missing "$key".');
  }
  final value = backup[key];
  if (value is! List) {
    throw FormatException('Backup "$key" must be a list.');
  }
  return value.map(_backupMap).toList();
}

Map<String, Object?> _backupMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Backup file contains invalid data.');
  }
  return value.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, Object?> _sqliteRow(Map<String, Object?> source) {
  return source.map((key, value) {
    if (value == null ||
        value is int ||
        value is double ||
        value is String ||
        value is List<int>) {
      return MapEntry(key, value);
    }
    if (value is bool) {
      return MapEntry(key, value ? 1 : 0);
    }
    return MapEntry(key, jsonEncode(value));
  });
}

int? _backupInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
