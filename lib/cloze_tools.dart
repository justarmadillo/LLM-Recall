import 'dart:convert';

class ClozeTools {
  static const answerColor = '#12805C';

  static final RegExp _clozePattern = RegExp(
    r'\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}',
    dotAll: true,
  );

  static bool hasCloze(String value) {
    return _clozePattern.hasMatch(value);
  }

  static bool fieldsContainCloze(Map<String, String> fields) {
    return fields.values.any(hasCloze);
  }

  static String questionText(String value) {
    return value.replaceAllMapped(_clozePattern, (match) {
      final hint = match.group(3)?.trim();
      if (hint != null && hint.isNotEmpty) {
        return '[ $hint ]';
      }
      return '[ ... ]';
    });
  }

  static String answerText(String value) {
    return value.replaceAllMapped(_clozePattern, (match) {
      return match.group(2)?.trim() ?? '';
    });
  }

  static String answerHtml(String value) {
    return value.replaceAllMapped(_clozePattern, (match) {
      final answer = match.group(2)?.trim() ?? '';
      final escapedAnswer = const HtmlEscape().convert(answer);
      return '<strong style="color:$answerColor;font-weight:800">$escapedAnswer</strong>';
    });
  }

  static List<int> clozeNumbers(String value) {
    return _clozePattern
        .allMatches(value)
        .map((match) => int.tryParse(match.group(1) ?? ''))
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
  }
}
