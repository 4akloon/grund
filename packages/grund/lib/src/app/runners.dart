/// Reads which runners to start from the command line.
abstract final class Runners {
  /// The flag that names the runners to start.
  static const flag = '--only';

  /// The names after `--only=a,b` or `--only a,b`, or `null` when the flag is
  /// absent (start everything).
  ///
  /// An empty list (`--only=`) selects nothing: the runners are prepared but
  /// not started.
  static Set<String>? fromArgs(List<String> args) {
    for (final (index, argument) in args.indexed) {
      if (argument == flag) {
        return _names(index + 1 < args.length ? args[index + 1] : '');
      }
      if (argument.startsWith('$flag=')) {
        return _names(argument.substring(flag.length + 1));
      }
    }
    return null;
  }

  static Set<String> _names(String list) => {
    for (final name in list.split(','))
      if (name.trim().isNotEmpty) name.trim(),
  };
}
