/// Quoting of a path for the `Next:` steps `init` prints.
abstract final class ShellWord {
  /// [word] as one POSIX-shell word: unchanged when it is made of safe
  /// characters, single-quoted otherwise. A word starting with `-` gets a
  /// `./` prefix first, so `cd` does not take it for an option.
  static String quote(String word) {
    final path = word.startsWith('-') ? './$word' : word;
    return _safe.hasMatch(path) ? path : "'${path.replaceAll("'", r"'\''")}'";
  }

  static final _safe = RegExp(r'^[\w./~:@%+=-]+$');
}
