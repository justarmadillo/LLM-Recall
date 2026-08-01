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
    this.textScale = 1,
  });

  final String value;
  final TextStyle? textStyle;
  final String emptyText;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    final html = toRenderableCardHtml(value.trim().isEmpty ? emptyText : value);
    final child = HtmlWidget(
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
    if ((textScale - 1).abs() < 0.001) {
      return child;
    }
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) {
      return child;
    }
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: MultipliedTextScaler(
          mediaQuery.textScaler,
          textScale.clamp(0.1, 4),
        ),
      ),
      child: child,
    );
  }
}

@visibleForTesting
class MultipliedTextScaler extends TextScaler {
  const MultipliedTextScaler(this.base, this.multiplier);

  final TextScaler base;
  final double multiplier;

  @override
  double scale(double fontSize) => base.scale(fontSize) * multiplier;

  @override
  // TextScaler still requires this compatibility getter.
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * multiplier;

  @override
  bool operator ==(Object other) {
    return other is MultipliedTextScaler &&
        other.base == base &&
        other.multiplier == multiplier;
  }

  @override
  int get hashCode => Object.hash(base, multiplier);
}

@visibleForTesting
String toRenderableCardHtml(String value) {
  final html = _restoreEscapedHtmlTags(value);
  if (_containsHtmlTag(html)) {
    return html;
  }
  if (_containsHtmlEntity(html)) {
    return html.replaceAll('\r\n', '\n').replaceAll('\n', '<br>');
  }
  return const HtmlEscape().convert(html).replaceAll('\n', '<br>');
}

bool _containsHtmlTag(String value) =>
    RegExp(r'<[a-zA-Z][^>]*>|</[a-zA-Z]+>').hasMatch(value);

bool _containsHtmlEntity(String value) => RegExp(r'&#?\w+;').hasMatch(value);

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
