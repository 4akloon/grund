import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

import 'package:tasks_api/src/web/home_markdown.dart';

void main() {
  test('lists open and done tasks, escaping Markdown in titles', () {
    final markdown = HomeMarkdown.of(const [
      Task(id: 1, title: r'a_b *c* [d] `e` \f'),
      Task(id: 2, title: 'done', done: true),
    ]);

    expect(
      markdown,
      '# Tasks\n\n'
      r'- [ ] a\_b \*c\* \[d\] \`e\` \\f'
      '\n- [x] done\n',
    );
  });

  group('a title cannot add structure', () {
    String line(String title) => HomeMarkdown.of([Task(id: 1, title: title)]);

    test('a newline and a heading stay in one list line', () {
      expect(line('x\n# Heading'), '# Tasks\n\n- [ ] x # Heading\n');
    });

    test('a newline and a checkbox item stay in one list line', () {
      expect(
        line('x\n- [x] fake'),
        '# Tasks\n\n'
        r'- [ ] x - \[x\] fake'
        '\n',
      );
    });

    test('tabs and runs of whitespace collapse to one space', () {
      expect(line('a \t\r\n  b'), '# Tasks\n\n- [ ] a b\n');
    });

    test('angle brackets and ampersands are escaped', () {
      expect(
        line('<script> & co'),
        '# Tasks\n\n'
        r'- [ ] \<script> \& co'
        '\n',
      );
    });
  });
}
