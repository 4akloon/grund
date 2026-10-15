/// Names a new package cannot have.
abstract final class ReservedNames {
  /// Why [name] cannot name a new package, or `null` when it can.
  static String? reasonFor(String name) {
    if (_reservedWords.contains(name)) return 'a Dart reserved word';
    if (_dependencies.contains(name)) {
      return 'a dependency of the new package';
    }
    return null;
  }

  static const _reservedWords = {
    'assert',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'extends',
    'false',
    'final',
    'finally',
    'for',
    'if',
    'in',
    'is',
    'new',
    'null',
    'rethrow',
    'return',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'var',
    'void',
    'while',
    'with',
  };

  static const _dependencies = {
    'grund',
    'grund_annotations',
    'grund_cli',
    'grund_io',
    'lints',
  };
}
