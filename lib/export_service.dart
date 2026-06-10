import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'csv_tools.dart';
import 'models.dart';

class ExportService {
  ExportService({CsvTools? csvTools}) : _csvTools = csvTools ?? CsvTools();

  final CsvTools _csvTools;

  String buildSessionCsv({
    required PreAnkiSession session,
    required List<Flashcard> cards,
  }) {
    return _csvTools.exportRows(
      headers: session.fieldNames,
      cards: cards.map((card) => card.fields).toList(),
      exportFields: session.exportFields,
      includeHeader: session.includeHeader,
    );
  }

  Future<String?> saveSessionCsv({
    required PreAnkiSession session,
    required List<Flashcard> cards,
    String? initialDirectory,
  }) async {
    final csv = buildSessionCsv(session: session, cards: cards);
    final safeName = session.title
        .trim()
        .replaceAll(RegExp(r'[^\w\s.-]+'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final fileName = '${safeName.isEmpty ? 'llm_recall_export' : safeName}.csv';
    final bytes = Uint8List.fromList(utf8.encode(csv));
    String? pickerInitialDirectory;
    if (initialDirectory != null && initialDirectory.trim().isNotEmpty) {
      final directory = Directory(initialDirectory);
      if (await directory.exists()) {
        pickerInitialDirectory = directory.path;
        try {
          final file = File(p.join(directory.path, fileName));
          await file.writeAsBytes(bytes);
          return file.path;
        } on FileSystemException {
          // Fall through to the save picker if a remembered folder is stale.
        }
      }
    }
    final selectedPath = await FilePicker.saveFile(
      dialogTitle: 'Export CSV',
      fileName: fileName,
      initialDirectory: pickerInitialDirectory,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: Platform.isAndroid || Platform.isIOS ? bytes : null,
    );
    if (selectedPath == null) {
      return null;
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await File(selectedPath).writeAsBytes(bytes);
    }
    return selectedPath;
  }
}
