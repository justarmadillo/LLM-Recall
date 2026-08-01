import 'package:flutter/material.dart';

import '../cloze_tools.dart';
import '../design_system.dart';
import '../models.dart';
import 'html_card_text.dart';

Future<Map<String, String>?> showCardEditorDialog({
  required BuildContext context,
  required Flashcard card,
  required List<String> fieldOrder,
  bool isClozeSession = false,
  String? clozeField,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) => _CardEditorDialog(
      mode: _CardEditorMode.edit,
      initialFields: card.fields,
      fieldOrder: fieldOrder,
      primaryField:
          clozeField ?? (fieldOrder.isEmpty ? null : fieldOrder.first),
      isClozeSession: isClozeSession,
      clozeField: clozeField,
    ),
  );
}

Future<Map<String, String>?> showAddCardDialog({
  required BuildContext context,
  required List<String> fieldOrder,
  required String primaryField,
  required bool isClozeSession,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) => _CardEditorDialog(
      mode: _CardEditorMode.add,
      initialFields: const {},
      fieldOrder: fieldOrder,
      primaryField: primaryField,
      isClozeSession: isClozeSession,
      clozeField: isClozeSession ? primaryField : null,
    ),
  );
}

enum _CardEditorMode { add, edit }

class _CardEditorDialog extends StatefulWidget {
  const _CardEditorDialog({
    required this.mode,
    required this.initialFields,
    required this.fieldOrder,
    required this.primaryField,
    required this.isClozeSession,
    required this.clozeField,
  });

  final _CardEditorMode mode;
  final Map<String, String> initialFields;
  final List<String> fieldOrder;
  final String? primaryField;
  final bool isClozeSession;
  final String? clozeField;

  @override
  State<_CardEditorDialog> createState() => _CardEditorDialogState();
}

class _CardEditorDialogState extends State<_CardEditorDialog> {
  late final Map<String, TextEditingController> _controllers;
  bool _showHtmlPreview = false;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in widget.fieldOrder)
        field: TextEditingController(text: widget.initialFields[field] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAddMode = widget.mode == _CardEditorMode.add;
    return AlertDialog(
      title: Text(isAddMode ? 'Add card' : 'Edit card'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorText != null) ...[
                _EditorError(text: _errorText!),
                const SizedBox(height: 12),
              ],
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _showHtmlPreview,
                onChanged: (value) {
                  setState(() => _showHtmlPreview = value);
                },
                secondary: const Icon(Icons.code_outlined),
                title: const Text('Preview HTML'),
                subtitle: const Text('Render every field as it will appear'),
              ),
              const SizedBox(height: 8),
              for (final entry in _controllers.entries) ...[
                Builder(
                  builder: (context) {
                    final isClozeField =
                        widget.isClozeSession && entry.key == widget.clozeField;
                    return TextField(
                      controller: entry.value,
                      minLines: isClozeField ? 3 : 1,
                      maxLines: isClozeField ? 8 : 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      contextMenuBuilder: (context, editableTextState) =>
                          _buildEditorContextMenu(
                            editableTextState,
                            entry.key,
                            includeClozeAction: isClozeField,
                          ),
                      decoration: InputDecoration(
                        labelText: entry.key,
                        prefixIcon: Icon(
                          isClozeField
                              ? Icons.data_object_outlined
                              : Icons.short_text_outlined,
                        ),
                      ),
                    );
                  },
                ),
                if (widget.isClozeSession && entry.key == widget.clozeField)
                  Align(
                    alignment: Alignment.centerRight,
                    child: _ClozeSelectionButton(
                      controller: entry.value,
                      onPressed: () => _wrapSelectedTextAsCloze(entry.key),
                    ),
                  ),
                if (_showHtmlPreview) ...[
                  const SizedBox(height: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: entry.value,
                    builder: (context, value, _) {
                      return AppSurface(
                        padding: const EdgeInsets.all(12),
                        radius: AppRadii.md,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${entry.key} preview',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: AppColors.inkMuted),
                            ),
                            const SizedBox(height: 6),
                            HtmlCardText(
                              value: value.text,
                              textStyle: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: AppColors.ink, height: 1.4),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: Icon(isAddMode ? Icons.add_outlined : Icons.save_outlined),
          label: Text(isAddMode ? 'Add' : 'Save'),
        ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
    );
  }

  String? _errorText;

  Widget _buildEditorContextMenu(
    EditableTextState editableTextState,
    String field, {
    required bool includeClozeAction,
  }) {
    final buttonItems = editableTextState.contextMenuButtonItems.toList();
    if (includeClozeAction && _hasActiveSelection(field)) {
      buttonItems.add(
        ContextMenuButtonItem(
          label: 'Cloze',
          type: ContextMenuButtonType.custom,
          onPressed: () {
            ContextMenuController.removeAny();
            _wrapSelectedTextAsCloze(field);
          },
        ),
      );
    }
    if (buttonItems.isEmpty) {
      return const SizedBox.shrink();
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  bool _hasActiveSelection(String field) {
    final controller = _controllers[field];
    if (controller == null) {
      return false;
    }
    final selection = controller.selection;
    return selection.isValid &&
        !selection.isCollapsed &&
        selection.start >= 0 &&
        selection.end <= controller.text.length;
  }

  void _wrapSelectedTextAsCloze(String field) {
    final controller = _controllers[field];
    if (controller == null || !_hasActiveSelection(field)) {
      return;
    }
    final selection = controller.selection;
    final start = selection.start;
    final end = selection.end;
    final nextNumber = ClozeTools.nextClozeNumber(controller.text);
    final selectedText = controller.text.substring(start, end);
    final insertedText = '{{c$nextNumber::$selectedText}}';
    final nextText = ClozeTools.wrapRange(
      value: controller.text,
      start: start,
      end: end,
      number: nextNumber,
    );
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + insertedText.length),
    );
    setState(() => _errorText = null);
  }

  void _save() {
    final fields = _controllers.map(
      (field, controller) => MapEntry(field, controller.text.trim()),
    );
    final primaryField = widget.primaryField;
    final primaryValue = primaryField == null ? '' : fields[primaryField] ?? '';
    if (primaryValue.isEmpty) {
      setState(() => _errorText = 'The front field cannot be empty.');
      return;
    }
    if (widget.mode == _CardEditorMode.add &&
        widget.isClozeSession &&
        !ClozeTools.hasCloze(primaryValue)) {
      setState(
        () =>
            _errorText = 'Cloze cards need at least one {{c1::...}} deletion.',
      );
      return;
    }
    Navigator.pop(context, fields);
  }
}

class _ClozeSelectionButton extends StatelessWidget {
  const _ClozeSelectionButton({
    required this.controller,
    required this.onPressed,
  });

  final TextEditingController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final selection = value.selection;
        final canCloze =
            selection.isValid &&
            !selection.isCollapsed &&
            selection.start >= 0 &&
            selection.end <= value.text.length;
        return IconButton(
          tooltip: 'Cloze selected text',
          onPressed: canCloze ? onPressed : null,
          icon: const Icon(Icons.data_object_outlined, size: 18),
          style: IconButton.styleFrom(
            minimumSize: const Size(40, 40),
            foregroundColor: canCloze ? AppColors.primary : AppColors.inkFaint,
            backgroundColor: canCloze
                ? const Color(0xFFE8F3FF)
                : AppColors.canvasSoft,
          ),
        );
      },
    );
  }
}

class _EditorError extends StatelessWidget {
  const _EditorError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
