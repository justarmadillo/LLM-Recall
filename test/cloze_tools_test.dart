import 'package:flutter_test/flutter_test.dart';
import 'package:preanki/cloze_tools.dart';

void main() {
  group('ClozeTools', () {
    test('renders cloze questions, answers, hints, and numbers', () {
      const text = 'The {{c1::mitochondrion::organelle}} makes {{c2::ATP}}.';

      expect(ClozeTools.hasCloze(text), isTrue);
      expect(ClozeTools.questionText(text), 'The [ organelle ] makes [ ... ].');
      expect(ClozeTools.answerText(text), 'The mitochondrion makes ATP.');
      expect(
        ClozeTools.answerHtml(text),
        'The <strong style="color:#12805C;font-weight:800">mitochondrion</strong> makes <strong style="color:#12805C;font-weight:800">ATP</strong>.',
      );
      expect(ClozeTools.clozeNumbers(text), [1, 2]);
    });

    test('escapes cloze answers before rendering html', () {
      const text = 'Use {{c1::<b>ATP</b> & energy}}.';

      expect(
        ClozeTools.answerHtml(text),
        'Use <strong style="color:#12805C;font-weight:800">&lt;b&gt;ATP&lt;&#47;b&gt; &amp; energy</strong>.',
      );
    });
  });
}
