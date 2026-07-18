import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../design_system.dart';

class HtmlCardText extends StatelessWidget {
  const HtmlCardText({
    super.key,
    required this.value,
    required this.textStyle,
    this.emptyText = '(empty)',
  });

  final String value;
  final TextStyle? textStyle;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final html = toRenderableCardHtml(value.trim().isEmpty ? emptyText : value);
    return HtmlWidget(
      html,
      textStyle: textStyle?.copyWith(letterSpacing: 0),
      customStylesBuilder: (element) {
        if (element.localName == 'img') {
          return {
            'max-width': '100%',
            'height': 'auto',
            'border-radius': '${AppRadii.md}px',
          };
        }
        if (element.localName == 'table') {
          return {'border-collapse': 'collapse', 'max-width': '100%'};
        }
        if (element.localName == 'td' || element.localName == 'th') {
          return {'border': '1px solid #e6e6e6', 'padding': '6px'};
        }
        return null;
      },
    );
  }
}

@visibleForTesting
String toRenderableCardHtml(String value) {
  final html = _restoreEscapedHtmlTags(value);
  if (_containsHtml(html)) {
    return html;
  }
  return const HtmlEscape().convert(html).replaceAll('\n', '<br>');
}

bool _containsHtml(String value) {
  return RegExp(r'<[a-zA-Z][^>]*>|</[a-zA-Z]+>|&#?\w+;').hasMatch(value);
}

String _restoreEscapedHtmlTags(String value) {
  return value.replaceAllMapped(_escapedHtmlTagPattern, (match) {
    return '<${_decodeEscapedTag(match.group(1)!)}>';
  });
}

String _decodeEscapedTag(String tag) {
  return tag
      .replaceAll('&#47;', '/')
      .replaceAll('&#x2F;', '/')
      .replaceAll('&#x2f;', '/')
      .replaceAll('&quot;', '"')
      .replaceAll('&#34;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}

final RegExp _escapedHtmlTagPattern = RegExp(
  r'&lt;((?:/|&#47;|&#x2[fF];)?[a-zA-Z][a-zA-Z0-9:-]*(?:\s+[^<>]*?)?\s*(?:/|&#47;|&#x2[fF];)?)&gt;',
);
