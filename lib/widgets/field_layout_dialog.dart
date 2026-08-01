import 'dart:collection';

import 'package:flutter/material.dart';

import '../design_system.dart';
import '../models.dart';

/// The field presentation chosen in [FieldLayoutDialog].
class FieldLayoutResult {
  FieldLayoutResult({
    required List<String> orderedFields,
    required this.frontField,
    required Iterable<String> frontFields,
  }) : orderedFields = UnmodifiableListView(List.of(orderedFields)),
       frontFields = UnmodifiableListView([
         for (final field in orderedFields)
           if (field == frontField || frontFields.contains(field)) field,
       ]);

  final List<String> orderedFields;
  final String frontField;
  final List<String> frontFields;

  /// Every field is displayed after the card is flipped, including the
  /// prompt and fields that also appear on the front.
  List<String> get revealFields => UnmodifiableListView(orderedFields);
}

/// Opens a dialog for choosing the review prompt and back-field order.
Future<FieldLayoutResult?> showFieldLayoutDialog(
  BuildContext context, {
  required PreAnkiSession session,
}) {
  return showDialog<FieldLayoutResult>(
    context: context,
    builder: (context) => FieldLayoutDialog(session: session),
  );
}

class FieldLayoutDialog extends StatefulWidget {
  const FieldLayoutDialog({super.key, required this.session});

  final PreAnkiSession session;

  @override
  State<FieldLayoutDialog> createState() => _FieldLayoutDialogState();
}

class _FieldLayoutDialogState extends State<FieldLayoutDialog> {
  late final List<String> _orderedFields;
  late final Set<String> _frontFields;
  late String _frontField;

  @override
  void initState() {
    super.initState();
    _orderedFields = List.of(widget.session.fieldNames);
    _frontField = _orderedFields.contains(widget.session.frontField)
        ? widget.session.frontField
        : (_orderedFields.isEmpty ? '' : _orderedFields.first);
    _frontFields = {
      for (final field in widget.session.frontFields)
        if (_orderedFields.contains(field)) field,
      if (_frontField.isNotEmpty) _frontField,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isCloze = widget.session.cardType == SessionCardType.cloze;
    // Leave enough of the dialog's height for the guidance and actions. The
    // field list scrolls independently when a note has many fields.
    final availableHeight = MediaQuery.sizeOf(context).height * 0.4;
    final listHeight = (_orderedFields.length * 108.0)
        .clamp(0.0, availableHeight)
        .toDouble();

    return AlertDialog(
      title: const Text('Arrange fields'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCloze
                  ? 'Select the field containing cloze deletions. It supplies '
                        'the review prompt and cloze answer. Arrange every field '
                        'in display order, then choose whether extra fields also '
                        'appear on the front.'
                  : 'Select the review prompt, arrange every field in display '
                        'order, then choose whether extra fields also appear on '
                        'the front.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: listHeight,
              child: RadioGroup<String>(
                groupValue: _frontField,
                onChanged: (field) {
                  if (field != null) {
                    setState(() {
                      _frontField = field;
                      _frontFields.add(field);
                    });
                  }
                },
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: _orderedFields.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) {
                    final field = _orderedFields[index];
                    final isFront = field == _frontField;
                    return _FieldLayoutRow(
                      key: ValueKey('field-layout-row-$field'),
                      field: field,
                      role: isFront
                          ? (isCloze ? 'Cloze prompt' : 'Prompt')
                          : 'Back ${_backPosition(index)}',
                      selected: isFront,
                      showsOnFront: _frontFields.contains(field),
                      index: index,
                      onSelected: () => setState(() {
                        _frontField = field;
                        _frontFields.add(field);
                      }),
                      onFrontChanged: isFront
                          ? null
                          : (value) => setState(() {
                              if (value) {
                                _frontFields.add(field);
                              } else {
                                _frontFields.remove(field);
                              }
                            }),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _orderedFields.isEmpty ? null : _save,
          child: const Text('Save'),
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

  int _backPosition(int index) {
    final frontIndex = _orderedFields.indexOf(_frontField);
    return index < frontIndex ? index + 1 : index;
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final field = _orderedFields.removeAt(oldIndex);
      _orderedFields.insert(newIndex, field);
    });
  }

  void _save() {
    Navigator.pop(
      context,
      FieldLayoutResult(
        orderedFields: List.of(_orderedFields),
        frontField: _frontField,
        frontFields: _frontFields,
      ),
    );
  }
}

class _FieldLayoutRow extends StatelessWidget {
  const _FieldLayoutRow({
    super.key,
    required this.field,
    required this.role,
    required this.selected,
    required this.showsOnFront,
    required this.index,
    required this.onSelected,
    required this.onFrontChanged,
  });

  final String field;
  final String role;
  final bool selected;
  final bool showsOnFront;
  final int index;
  final VoidCallback onSelected;
  final ValueChanged<bool>? onFrontChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: SizedBox(
        height: 104,
        child: Column(
          children: [
            Expanded(
              child: InkWell(
                onTap: onSelected,
                child: Row(
                  children: [
                    Radio<String>(
                      key: ValueKey('field-layout-radio-$field'),
                      value: field,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            field,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            role,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.inkMuted,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: 'Drag to reorder $field',
                      child: ReorderableDragStartListener(
                        key: ValueKey('field-layout-drag-$field'),
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          child: Icon(
                            Icons.drag_handle,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xl,
                right: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selected
                          ? 'Front & back (prompt)'
                          : (showsOnFront ? 'Front & back' : 'Back only'),
                      key: ValueKey('field-layout-side-label-$field'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: selected
                            ? AppColors.primary
                            : AppColors.inkMuted,
                        fontWeight: selected || showsOnFront
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  Switch(
                    key: ValueKey('field-layout-front-$field'),
                    value: showsOnFront,
                    onChanged: onFrontChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
