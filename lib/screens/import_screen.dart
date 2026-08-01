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
import '../widgets/html_card_text.dart';
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
  final _fieldMappings = <_ImportFieldMapping>[];

  CsvImportResult? _result;
  bool _hasHeader = false;
  bool _includeHeader = true;
  ImportFormat _format = ImportFormat.questionAnswer;
  int _primarySourceIndex = 0;
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
    for (final mapping in _fieldMappings) {
      mapping.controller.dispose();
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
                fieldMappings: _fieldMappings,
                format: _format,
                primarySourceIndex: _primarySourceIndex,
                includeHeader: _includeHeader,
                onFormatChanged: (format) {
                  setState(() {
                    _format = format;
                    _primarySourceIndex = _suggestPrimarySourceIndex();
                  });
                },
                onPrimaryChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _primarySourceIndex = value);
                },
                onFrontChanged: (sourceIndex, value) {
                  setState(() {
                    _fieldMappings
                            .firstWhere(
                              (mapping) => mapping.sourceIndex == sourceIndex,
                            )
                            .showOnFront =
                        value;
                  });
                },
                onReorderItem: _reorderFields,
                onIncludeHeaderChanged: (value) {
                  setState(() => _includeHeader = value);
                },
                onFieldChanged: () => setState(() {}),
              ),
              const SizedBox(height: 16),
              _PreviewTable(
                fieldNames: fieldNames,
                rows: _rowsInFieldOrder(dataRows.take(5)),
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
    return _fieldMappings
        .map((mapping) => mapping.controller.text.trim())
        .toList();
  }

  List<List<String>> _rowsInFieldOrder(Iterable<List<String>> rows) {
    return reorderRowsBySourceIndices(
      rows,
      _fieldMappings.map((mapping) => mapping.sourceIndex),
    );
  }

  void _reorderFields(int oldIndex, int newIndex) {
    setState(() {
      final mapping = _fieldMappings.removeAt(oldIndex);
      _fieldMappings.insert(newIndex, mapping);
    });
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
    for (final mapping in _fieldMappings) {
      mapping.controller.dispose();
    }
    _fieldMappings.clear();
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
    _fieldMappings.addAll(
      uniqueFields.indexed.map(
        (entry) => _ImportFieldMapping(
          sourceIndex: entry.$1,
          controller: TextEditingController(text: entry.$2),
        ),
      ),
    );
    _format = _dataLooksLikeCloze()
        ? ImportFormat.cloze
        : ImportFormat.questionAnswer;
    _primarySourceIndex = _suggestPrimarySourceIndex();
  }

  Future<void> _createSession(List<List<String>> dataRows) async {
    final appState = AppScope.of(context);
    final validationError = _validate(dataRows);
    if (validationError != null) {
      setState(() => _formError = validationError);
      return;
    }
    final fields = _fieldNames;
    final primaryMapping = _fieldMappings.firstWhere(
      (mapping) => mapping.sourceIndex == _primarySourceIndex,
    );
    final primaryField = primaryMapping.controller.text.trim();
    final answerFields = [
      for (final mapping in _fieldMappings)
        if (mapping.sourceIndex != _primarySourceIndex)
          mapping.controller.text.trim(),
    ];
    final frontFields = [
      for (final mapping in _fieldMappings)
        if (mapping.sourceIndex == _primarySourceIndex || mapping.showOnFront)
          mapping.controller.text.trim(),
    ];
    final sessionId = await appState.createSessionFromImport(
      title: _titleController.text,
      source: _sourceName ?? 'Pasted CSV',
      cardType: _format == ImportFormat.cloze
          ? SessionCardType.cloze
          : SessionCardType.questionAnswer,
      rows: _rowsInFieldOrder(dataRows),
      fieldNames: fields,
      frontField: primaryField,
      frontFields: frontFields,
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
        _formError = appState.errorMessage ?? 'Could not create the session.';
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
    if (!_fieldMappings.any(
      (mapping) => mapping.sourceIndex == _primarySourceIndex,
    )) {
      return _format == ImportFormat.cloze
          ? 'Choose the cloze field.'
          : 'Choose the question field.';
    }
    if (_format == ImportFormat.questionAnswer && fields.length < 2) {
      return 'Question / answer imports need at least one answer field.';
    }
    if (_format == ImportFormat.cloze &&
        !_rowsContainCloze(dataRows, _primarySourceIndex)) {
      return 'The selected cloze field does not contain {{c1::...}} text.';
    }
    return null;
  }

  int _suggestPrimarySourceIndex() {
    if (_fieldMappings.isEmpty) {
      return 0;
    }
    if (_format == ImportFormat.cloze) {
      final result = _result;
      if (result != null) {
        final dataRows = result.dataRows(headerOverride: _hasHeader);
        for (final mapping in _fieldMappings) {
          if (_rowsContainCloze(dataRows, mapping.sourceIndex)) {
            return mapping.sourceIndex;
          }
        }
      }
    }
    if (_fieldMappings.any(
      (mapping) => mapping.sourceIndex == _primarySourceIndex,
    )) {
      return _primarySourceIndex;
    }
    return _fieldMappings.first.sourceIndex;
  }

  bool _dataLooksLikeCloze() {
    final result = _result;
    if (result == null) {
      return false;
    }
    final dataRows = result.dataRows(headerOverride: _hasHeader);
    for (final mapping in _fieldMappings) {
      if (_rowsContainCloze(dataRows, mapping.sourceIndex)) {
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

@visibleForTesting
List<List<String>> reorderRowsBySourceIndices(
  Iterable<List<String>> rows,
  Iterable<int> sourceIndices,
) {
  final indices = sourceIndices.toList();
  return rows.map((row) {
    return [
      for (final sourceIndex in indices)
        sourceIndex >= 0 && sourceIndex < row.length ? row[sourceIndex] : '',
    ];
  }).toList();
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
    required this.fieldMappings,
    required this.format,
    required this.primarySourceIndex,
    required this.includeHeader,
    required this.onFormatChanged,
    required this.onPrimaryChanged,
    required this.onFrontChanged,
    required this.onReorderItem,
    required this.onIncludeHeaderChanged,
    required this.onFieldChanged,
  });

  final List<_ImportFieldMapping> fieldMappings;
  final ImportFormat format;
  final int primarySourceIndex;
  final bool includeHeader;
  final ValueChanged<ImportFormat> onFormatChanged;
  final ValueChanged<int?> onPrimaryChanged;
  final void Function(int sourceIndex, bool value) onFrontChanged;
  final ReorderCallback onReorderItem;
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
          Text(
            'Drag fields into review and export order. The prompt always '
            'appears on the front and back; choose whether each extra field '
            'also appears on the front.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(height: 8),
          RadioGroup<int>(
            groupValue: primarySourceIndex,
            onChanged: onPrimaryChanged,
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: fieldMappings.length,
              onReorderItem: onReorderItem,
              itemBuilder: (context, index) {
                final mapping = fieldMappings[index];
                final isPrimary = mapping.sourceIndex == primarySourceIndex;
                return Padding(
                  key: ValueKey('import-field-${mapping.sourceIndex}'),
                  padding: EdgeInsets.only(
                    bottom: index < fieldMappings.length - 1 ? 12 : 0,
                  ),
                  child: AppSurface(
                    padding: const EdgeInsets.all(12),
                    radius: AppRadii.md,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<int>(
                                key: ValueKey(
                                  'import-primary-${mapping.sourceIndex}',
                                ),
                                value: mapping.sourceIndex,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(
                                  format == ImportFormat.cloze
                                      ? 'Use as cloze prompt'
                                      : 'Use as question prompt',
                                ),
                                subtitle: Text(
                                  isPrimary
                                      ? 'Selected prompt field'
                                      : 'Select this field as the prompt',
                                ),
                              ),
                            ),
                            ReorderableDragStartListener(
                              key: ValueKey(
                                'import-field-drag-${mapping.sourceIndex}',
                              ),
                              index: index,
                              child: const Tooltip(
                                message: 'Drag to reorder field',
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: mapping.controller,
                          onChanged: (_) => onFieldChanged(),
                          decoration: InputDecoration(
                            labelText: isPrimary
                                ? (format == ImportFormat.cloze
                                      ? 'Cloze field'
                                      : 'Question field')
                                : (format == ImportFormat.cloze
                                      ? 'Extra field'
                                      : 'Answer field'),
                            prefixIcon: const Icon(Icons.short_text_outlined),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isPrimary
                                    ? 'Front & back (prompt)'
                                    : (mapping.showOnFront
                                          ? 'Front & back'
                                          : 'Back only'),
                                key: ValueKey(
                                  'import-front-label-${mapping.sourceIndex}',
                                ),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: isPrimary
                                          ? AppColors.primary
                                          : AppColors.inkMuted,
                                      fontWeight:
                                          isPrimary || mapping.showOnFront
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                              ),
                            ),
                            Switch(
                              key: ValueKey(
                                'import-front-toggle-${mapping.sourceIndex}',
                              ),
                              value: isPrimary || mapping.showOnFront,
                              onChanged: isPrimary
                                  ? null
                                  : (value) => onFrontChanged(
                                      mapping.sourceIndex,
                                      value,
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
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
                            child: HtmlCardText(
                              value: index < row.length ? row[index] : '',
                              textStyle: Theme.of(context).textTheme.bodyMedium,
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

class _ImportFieldMapping {
  _ImportFieldMapping({required this.sourceIndex, required this.controller})
    : showOnFront = false;

  final int sourceIndex;
  final TextEditingController controller;
  bool showOnFront;
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
