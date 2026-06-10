import 'package:flutter/material.dart';

import '../design_system.dart';
import '../models.dart';

Future<Map<String, String>?> showCardEditorDialog({
  required BuildContext context,
  required Flashcard card,
  required List<String> fieldOrder,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) => _CardEditorDialog(card: card, fieldOrder: fieldOrder),
  );
}

class _CardEditorDialog extends StatefulWidget {
  const _CardEditorDialog({required this.card, required this.fieldOrder});

  final Flashcard card;
  final List<String> fieldOrder;

  @override
  State<_CardEditorDialog> createState() => _CardEditorDialogState();
}

class _CardEditorDialogState extends State<_CardEditorDialog> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in widget.fieldOrder)
        field: TextEditingController(text: widget.card.fields[field] ?? ''),
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
    return AlertDialog(
      title: const Text('Edit card'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in _controllers.entries) ...[
                TextField(
                  controller: entry.value,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: entry.key,
                    prefixIcon: const Icon(Icons.short_text_outlined),
                  ),
                ),
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
          onPressed: () {
            Navigator.pop(
              context,
              _controllers.map(
                (field, controller) => MapEntry(field, controller.text.trim()),
              ),
            );
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
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
}
