import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../cloze_tools.dart';
import '../csv_tools.dart';
import '../design_system.dart';
import '../main.dart';
import '../models.dart';
import 'session_screen.dart';

enum ImportFormat {
  questionAnswer,
  cloze;

  String get label {
    return switch (this) {
      ImportFormat.questionAnswer => 'Question / answer',
      ImportFormat.cloze => 'Cloze',
    };
  }
}

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, this.initialCsvText, this.initialSourceName});

  final String? initialCsvText;
  final String? initialSourceName;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _csvTools = CsvTools();
  final _textController = TextEditingController();
  final _titleController = TextEditingController();
  final _fieldControllers = <TextEditingController>[];

  CsvImportResult? _result;
  bool _hasHeader = false;
  bool _includeHeader = true;
  ImportFormat _format = ImportFormat.questionAnswer;
  int _primaryIndex = 0;
  String? _sourceName;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final initialText = widget.initialCsvText;
    if (initialText != null && initialText.trim().isNotEmpty) {
      _sourceName = widget.initialSourceName ?? 'Imported CSV';
      _textController.text = initialText;
      Future.microtask(() {
        if (mounted) {
          _parse(initialText);
        }
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    for (final controller in _fieldControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    final result = _result;
    final fieldNames = _fieldNames;
    final dataRows = result?.dataRows(headerOverride: _hasHeader) ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import CSV'),
        actions: [
          if (_sourceName != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Center(
                child: Tooltip(
                  message: _sourceName!,
                  child: const AppIconTile(
                    icon: Icons.insert_drive_file_outlined,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _InputPanel(
              controller: _textController,
              onPickFile: _pickFile,
              onPasteClipboard: _pasteClipboard,
              onParse: () => _parse(_textController.text),
            ),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              AppErrorBanner(message: _formError!),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              _ImportSummary(
                result: result,
                dataRowCount: dataRows.length,
                hasHeader: _hasHeader,
                onHeaderChanged: (value) {
                  setState(() {
                    _hasHeader = value;
                    _includeHeader = value;
                    _resetMapping();
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Session title',
                  prefixIcon: Icon(Icons.drive_file_rename_outline),
                ),
              ),
              const SizedBox(height: 16),
              _MappingPanel(
                fieldControllers: _fieldControllers,
                format: _format,
                primaryIndex: _primaryIndex,
                includeHeader: _includeHeader,
                onFormatChanged: (format) {
                  setState(() {
                    _format = format;
                    _primaryIndex = _suggestPrimaryIndex();
                  });
                },
                onPrimaryChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _primaryIndex = value);
                },
                onIncludeHeaderChanged: (value) {
                  setState(() => _includeHeader = value);
                },
                onFieldChanged: () => setState(() {}),
              ),
              const SizedBox(height: 16),
              _PreviewTable(
                fieldNames: fieldNames,
                rows: dataRows.take(5).toList(),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: appState.isBusy
                    ? null
                    : () => _createSession(dataRows),
                icon: appState.isBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.playlist_add_check_outlined),
                label: const Text('Create session'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> get _fieldNames {
    return _fieldControllers
        .map((controller) => controller.text.trim())
        .toList();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'tsv', 'txt'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.single;
      final content = await _readPickedFileText(file);
      if (!mounted) {
        return;
      }
      _sourceName = file.name;
      _textController.text = content;
      _parse(content);
    } on FileSystemException {
      if (mounted) {
        setState(() => _formError = 'Could not read that file.');
      }
    } on FormatException {
      if (mounted) {
        setState(() => _formError = 'That file is not valid text.');
      }
    }
  }

  Future<String> _readPickedFileText(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes != null) {
      return _csvTools.decodeBytes(bytes);
    }
    final path = file.path;
    if (path == null) {
      throw const FileSystemException('Could not read picked file.');
    }
    return _csvTools.decodeBytes(await File(path).readAsBytes());
  }

  void _setFormError(String message) {
    if (mounted) {
      setState(() => _formError = message);
    }
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) {
      return;
    }
    if (data?.text == null || data!.text!.trim().isEmpty) {
      _setFormError('Clipboard does not contain CSV text.');
      return;
    }
    _sourceName = 'Clipboard';
    _textController.text = data.text!;
    _parse(data.text!);
  }

  void _parse(String input) {
    final CsvImportResult parsed;
    try {
      parsed = _csvTools.parse(input);
    } on FormatException {
      _setFormError('Could not parse that CSV text.');
      return;
    }
    if (parsed.rows.isEmpty) {
      setState(() {
        _result = null;
        _formError = 'Paste or choose a CSV with at least one row.';
      });
      return;
    }
    setState(() {
      _result = parsed;
      _hasHeader = parsed.hasHeader;
      _includeHeader = parsed.hasHeader;
      _formError = null;
      _titleController.text = _sourceName == null
          ? 'CSV review ${DateFormat('MMM d, HH:mm').format(DateTime.now())}'
          : _sourceName!.replaceFirst(RegExp(r'\.(csv|tsv|txt)$'), '');
      _resetMapping();
    });
  }

  void _resetMapping() {
    for (final controller in _fieldControllers) {
      controller.dispose();
    }
    _fieldControllers.clear();
    final result = _result;
    if (result == null || result.rows.isEmpty) {
      return;
    }
    final fields = _hasHeader
        ? result.inferredHeaders
        : List.generate(
            result.rows.first.length,
            (index) => 'Column ${index + 1}',
          );
    final uniqueFields = _uniqueFieldNames(fields);
    _fieldControllers.addAll(
      uniqueFields.map((field) => TextEditingController(text: field)),
    );
    _format = _dataLooksLikeCloze()
        ? ImportFormat.cloze
        : ImportFormat.questionAnswer;
    _primaryIndex = _suggestPrimaryIndex();
  }

  Future<void> _createSession(List<List<String>> dataRows) async {
    final appState = AppScope.of(context);
    final validationError = _validate(dataRows);
    if (validationError != null) {
      setState(() => _formError = validationError);
      return;
    }
    final fields = _fieldNames;
    final primaryField = fields[_primaryIndex];
    final answerFields = [
      for (final field in fields)
        if (field != primaryField) field,
    ];
    final sessionId = await appState.createSessionFromImport(
      title: _titleController.text,
      source: _sourceName ?? 'Pasted CSV',
      cardType: _format == ImportFormat.cloze
          ? SessionCardType.cloze
          : SessionCardType.questionAnswer,
      rows: dataRows,
      fieldNames: fields,
      frontField: primaryField,
      revealFields: answerFields,
      exportFields: fields,
      includeHeader: _includeHeader,
    );
    if (!mounted) {
      return;
    }
    if (sessionId == null) {
      // createSessionFromImport reports failures via appState.errorMessage;
      // surface it here so the user is not left staring at a silent screen.
      setState(() {
        _formError =
            appState.errorMessage ?? 'Could not create the session.';
      });
      return;
    }
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(builder: (_) => SessionScreen(sessionId: sessionId)),
    );
  }

  String? _validate(List<List<String>> dataRows) {
    if (dataRows.isEmpty) {
      return 'There are no card rows to import.';
    }
    final fields = _fieldNames;
    if (fields.any((field) => field.isEmpty)) {
      return 'Every field needs a name.';
    }
    if (fields.toSet().length != fields.length) {
      return 'Field names must be unique.';
    }
    if (_primaryIndex < 0 || _primaryIndex >= fields.length) {
      return _format == ImportFormat.cloze
          ? 'Choose the cloze field.'
          : 'Choose the question field.';
    }
    if (_format == ImportFormat.questionAnswer && fields.length < 2) {
      return 'Question / answer imports need at least one answer field.';
    }
    if (_format == ImportFormat.cloze &&
        !_rowsContainCloze(dataRows, _primaryIndex)) {
      return 'The selected cloze field does not contain {{c1::...}} text.';
    }
    return null;
  }

  int _suggestPrimaryIndex() {
    if (_fieldControllers.isEmpty) {
      return 0;
    }
    if (_format == ImportFormat.cloze) {
      final result = _result;
      if (result != null) {
        final dataRows = result.dataRows(headerOverride: _hasHeader);
        for (var index = 0; index < _fieldControllers.length; index += 1) {
          if (_rowsContainCloze(dataRows, index)) {
            return index;
          }
        }
      }
    }
    return _primaryIndex.clamp(0, _fieldControllers.length - 1);
  }

  bool _dataLooksLikeCloze() {
    final result = _result;
    if (result == null) {
      return false;
    }
    final dataRows = result.dataRows(headerOverride: _hasHeader);
    for (var index = 0; index < _fieldControllers.length; index += 1) {
      if (_rowsContainCloze(dataRows, index)) {
        return true;
      }
    }
    return false;
  }

  bool _rowsContainCloze(List<List<String>> rows, int index) {
    return rows.any((row) {
      return index < row.length && ClozeTools.hasCloze(row[index]);
    });
  }
}

class _InputPanel extends StatelessWidget {
  const _InputPanel({
    required this.controller,
    required this.onPickFile,
    required this.onPasteClipboard,
    required this.onParse,
  });

  final TextEditingController controller;
  final VoidCallback onPickFile;
  final VoidCallback onPasteClipboard;
  final VoidCallback onParse;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onPickFile,
                icon: const Icon(Icons.attach_file_outlined),
                label: const Text('Choose file'),
              ),
              OutlinedButton.icon(
                onPressed: onPasteClipboard,
                icon: const Icon(Icons.content_paste_outlined),
                label: const Text('Paste clipboard'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'CSV text',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onParse,
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('Preview and map fields'),
          ),
        ],
      ),
    );
  }
}

class _ImportSummary extends StatelessWidget {
  const _ImportSummary({
    required this.result,
    required this.dataRowCount,
    required this.hasHeader,
    required this.onHeaderChanged,
  });

  final CsvImportResult result;
  final int dataRowCount;
  final bool hasHeader;
  final ValueChanged<bool> onHeaderChanged;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$dataRowCount cards detected',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                'Delimiter: ${result.delimiter == '\t' ? 'tab' : result.delimiter}',
              ),
              Text('Columns: ${result.rows.first.length}'),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: hasHeader,
            onChanged: onHeaderChanged,
            title: const Text('First row contains field names'),
          ),
        ],
      ),
    );
  }
}

class _MappingPanel extends StatelessWidget {
  const _MappingPanel({
    required this.fieldControllers,
    required this.format,
    required this.primaryIndex,
    required this.includeHeader,
    required this.onFormatChanged,
    required this.onPrimaryChanged,
    required this.onIncludeHeaderChanged,
    required this.onFieldChanged,
  });

  final List<TextEditingController> fieldControllers;
  final ImportFormat format;
  final int primaryIndex;
  final bool includeHeader;
  final ValueChanged<ImportFormat> onFormatChanged;
  final ValueChanged<int?> onPrimaryChanged;
  final ValueChanged<bool> onIncludeHeaderChanged;
  final VoidCallback onFieldChanged;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Field mapping', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<ImportFormat>(
            segments: const [
              ButtonSegment(
                value: ImportFormat.questionAnswer,
                icon: Icon(Icons.question_answer_outlined),
                label: Text('Q / A'),
              ),
              ButtonSegment(
                value: ImportFormat.cloze,
                icon: Icon(Icons.data_object_outlined),
                label: Text('Cloze'),
              ),
            ],
            selected: {format},
            onSelectionChanged: (selection) {
              onFormatChanged(selection.single);
            },
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < fieldControllers.length; index += 1) ...[
            AppSurface(
              padding: const EdgeInsets.all(12),
              radius: AppRadii.md,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: index == primaryIndex,
                    onChanged: (_) => onPrimaryChanged(index),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: fieldControllers[index],
                      onChanged: (_) => onFieldChanged(),
                      decoration: InputDecoration(
                        labelText: index == primaryIndex
                            ? (format == ImportFormat.cloze
                                  ? 'Cloze field'
                                  : 'Question field')
                            : (format == ImportFormat.cloze
                                  ? 'Extra field'
                                  : 'Answer field'),
                        prefixIcon: const Icon(Icons.short_text_outlined),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (index == primaryIndex) ...[
              const SizedBox(height: 8),
              AppBadge(
                label: format == ImportFormat.cloze
                    ? 'Cloze prompt'
                    : 'Question side',
                icon: format == ImportFormat.cloze
                    ? Icons.data_object_outlined
                    : Icons.quiz_outlined,
              ),
            ] else ...[
              const SizedBox(height: 8),
              AppBadge(
                label: 'Shows on back',
                icon: Icons.visibility_outlined,
                color: AppColors.inkMuted,
              ),
            ],
            if (index < fieldControllers.length - 1) ...[
              const SizedBox(height: 12),
            ],
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: includeHeader,
            onChanged: onIncludeHeaderChanged,
            title: const Text('Export header row'),
          ),
        ],
      ),
    );
  }
}

class _PreviewTable extends StatelessWidget {
  const _PreviewTable({required this.fieldNames, required this.rows});

  final List<String> fieldNames;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preview', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                for (final field in fieldNames) DataColumn(label: Text(field)),
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    cells: [
                      for (var index = 0; index < fieldNames.length; index += 1)
                        DataCell(
                          SizedBox(
                            width: 180,
                            child: Text(
                              index < row.length ? row[index] : '',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<String> _uniqueFieldNames(List<String> fields) {
  final counts = <String, int>{};
  return fields.map((field) {
    final base = field.trim().isEmpty ? 'Field' : field.trim();
    final count = counts[base] ?? 0;
    counts[base] = count + 1;
    return count == 0 ? base : '$base ${count + 1}';
  }).toList();
}
