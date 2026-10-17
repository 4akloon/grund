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
}
