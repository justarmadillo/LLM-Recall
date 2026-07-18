import 'package:flutter_test/flutter_test.dart';
import 'package:preanki/cloze_tools.dart';
import 'package:preanki/widgets/html_card_text.dart';

void main() {
  group('toRenderableCardHtml', () {
    test('keeps plain text safe while converting newlines to breaks', () {
      expect(toRenderableCardHtml('2 < 3\nAT&T'), '2 &lt; 3<br>AT&amp;T');
    });

    test('restores escaped html tags from Anki-style fields', () {
      expect(toRenderableCardHtml('alpha&lt;br&gt;beta'), 'alpha<br>beta');
      expect(
        toRenderableCardHtml(
          '&lt;span style=&quot;color:red&quot;&gt;red&lt;&#47;span&gt;',
        ),
        '<span style="color:red">red</span>',
      );
    });

    test('renders html inside escaped cloze answers', () {
      final answerHtml = ClozeTools.answerHtml(
        'Line {{c1::alpha<br>beta}} and {{c2::<b>gamma</b>}}.',
      );

      expect(
        toRenderableCardHtml(answerHtml),
        'Line <strong style="color:#12805C;font-weight:800">alpha<br>beta</strong> and <strong style="color:#12805C;font-weight:800"><b>gamma</b></strong>.',
      );
    });
  });
}
