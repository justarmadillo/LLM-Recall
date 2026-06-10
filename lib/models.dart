import 'dart:convert';

enum CardStatus {
  kept,
  deleted;

  static CardStatus fromStorage(String value) {
    return value == deleted.name ? deleted : kept;
  }
}

enum ReviewState {
  newCard,
  again,
  learned;

  String get storageValue {
    return switch (this) {
      ReviewState.newCard => 'new',
      ReviewState.again => 'again',
      ReviewState.learned => 'learned',
    };
  }

  String get label {
    return switch (this) {
      ReviewState.newCard => 'New',
      ReviewState.again => 'Again',
      ReviewState.learned => 'Learned',
    };
  }

  static ReviewState fromStorage(String value) {
    return switch (value) {
      'again' => ReviewState.again,
      'learned' => ReviewState.learned,
      _ => ReviewState.newCard,
    };
  }
}

enum CardFilter { all, kept, learning, learned, deleted }

class PreAnkiSession {
  const PreAnkiSession({
    this.id,
    required this.title,
    required this.source,
    required this.fieldNames,
    required this.frontField,
    required this.revealFields,
    required this.exportFields,
    required this.includeHeader,
    required this.totalCards,
    required this.reviewIndex,
    required this.createdAt,
    required this.updatedAt,
    this.deletedCount = 0,
    this.learnedCount = 0,
    this.againCount = 0,
  });

  final int? id;
  final String title;
  final String source;
  final List<String> fieldNames;
  final String frontField;
  final List<String> revealFields;
  final List<String> exportFields;
  final bool includeHeader;
  final int totalCards;
  final int reviewIndex;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int deletedCount;
  final int learnedCount;
  final int againCount;

  int get keptCount => totalCards - deletedCount;

  int get learningCount => keptCount - learnedCount;

  double get progress {
    if (keptCount <= 0) {
      return 0;
    }
    return (learnedCount.clamp(0, keptCount)) / keptCount;
  }

  PreAnkiSession copyWith({
    int? id,
    String? title,
    String? source,
    List<String>? fieldNames,
    String? frontField,
    List<String>? revealFields,
    List<String>? exportFields,
    bool? includeHeader,
    int? totalCards,
    int? reviewIndex,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? deletedCount,
    int? learnedCount,
    int? againCount,
  }) {
    return PreAnkiSession(
      id: id ?? this.id,
      title: title ?? this.title,
      source: source ?? this.source,
      fieldNames: fieldNames ?? this.fieldNames,
      frontField: frontField ?? this.frontField,
      revealFields: revealFields ?? this.revealFields,
      exportFields: exportFields ?? this.exportFields,
      includeHeader: includeHeader ?? this.includeHeader,
      totalCards: totalCards ?? this.totalCards,
      reviewIndex: reviewIndex ?? this.reviewIndex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedCount: deletedCount ?? this.deletedCount,
      learnedCount: learnedCount ?? this.learnedCount,
      againCount: againCount ?? this.againCount,
    );
  }

  Map<String, Object?> toDb() {
    return {
      'id': id,
      'title': title,
      'source': source,
      'field_names': jsonEncode(fieldNames),
      'front_field': frontField,
      'reveal_fields': jsonEncode(revealFields),
      'export_fields': jsonEncode(exportFields),
      'include_header': includeHeader ? 1 : 0,
      'total_cards': totalCards,
      'review_index': reviewIndex,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory PreAnkiSession.fromDb(
    Map<String, Object?> row, {
    int deletedCount = 0,
    int learnedCount = 0,
    int againCount = 0,
  }) {
    return PreAnkiSession(
      id: row['id'] as int?,
      title: row['title'] as String,
      source: row['source'] as String,
      fieldNames: _decodeStringList(row['field_names'] as String?),
      frontField: row['front_field'] as String,
      revealFields: _decodeStringList(row['reveal_fields'] as String?),
      exportFields: _decodeStringList(row['export_fields'] as String?),
      includeHeader: (row['include_header'] as int? ?? 1) == 1,
      totalCards: row['total_cards'] as int? ?? 0,
      reviewIndex: row['review_index'] as int? ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      deletedCount: deletedCount,
      learnedCount: learnedCount,
      againCount: againCount,
    );
  }
}

class Flashcard {
  const Flashcard({
    this.id,
    required this.sessionId,
    required this.originalIndex,
    required this.fields,
    required this.status,
    this.reviewState = ReviewState.newCard,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int sessionId;
  final int originalIndex;
  final Map<String, String> fields;
  final CardStatus status;
  final ReviewState reviewState;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDeleted => status == CardStatus.deleted;

  bool get isLearned => reviewState == ReviewState.learned;

  bool get isLearning => status == CardStatus.kept && !isLearned;

  Flashcard copyWith({
    int? id,
    int? sessionId,
    int? originalIndex,
    Map<String, String>? fields,
    CardStatus? status,
    ReviewState? reviewState,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Flashcard(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      originalIndex: originalIndex ?? this.originalIndex,
      fields: fields ?? this.fields,
      status: status ?? this.status,
      reviewState: reviewState ?? this.reviewState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toDb() {
    return {
      'id': id,
      'session_id': sessionId,
      'original_index': originalIndex,
      'fields_json': jsonEncode(fields),
      'status': status.name,
      'review_state': reviewState.storageValue,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Flashcard.fromDb(Map<String, Object?> row) {
    return Flashcard(
      id: row['id'] as int?,
      sessionId: row['session_id'] as int,
      originalIndex: row['original_index'] as int,
      fields: _decodeStringMap(row['fields_json'] as String?),
      status: CardStatus.fromStorage(row['status'] as String? ?? 'kept'),
      reviewState: ReviewState.fromStorage(
        row['review_state'] as String? ?? 'new',
      ),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}

List<String> _decodeStringList(String? raw) {
  if (raw == null || raw.isEmpty) {
    return const [];
  }
  final decoded = jsonDecode(raw) as List<dynamic>;
  return decoded.map((value) => value.toString()).toList();
}

Map<String, String> _decodeStringMap(String? raw) {
  if (raw == null || raw.isEmpty) {
    return const {};
  }
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded.map((key, value) => MapEntry(key, value?.toString() ?? ''));
}
