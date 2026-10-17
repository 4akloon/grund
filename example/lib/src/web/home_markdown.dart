import '../tasks/task.dart';

/// The home page as Markdown, for the alternate representation of `/`.
abstract final class HomeMarkdown {
  static final _whitespace = RegExp(r'\s+');
  static final _special = RegExp(r'[\\*_\[\]`<&]');

  /// A `# Tasks` heading and a checklist of [tasks], one item per task.
  static String of(List<Task> tasks) {
    final items = [
      for (final task in tasks)
        '- [${task.done ? 'x' : ' '}] ${_escape(task.title)}',
    ];
    return ['# Tasks', '', ...items, ''].join('\n');
  }

  // Whitespace first: a newline would start a new block of Markdown.
  static String _escape(String title) => title
      .replaceAll(_whitespace, ' ')
      .replaceAllMapped(_special, (m) => '\\${m[0]}');
}
