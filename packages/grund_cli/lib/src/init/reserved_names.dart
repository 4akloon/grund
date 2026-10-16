/// Names a new package cannot have.
abstract final class ReservedNames {
  /// Why [name] cannot name a new package whose pubspec names
  /// [dependencies], or `null` when it can.
  static String? reasonFor(String name, Set<String> dependencies) {
    if (_reservedWords.contains(name)) return 'a Dart reserved word';
    if (dependencies.contains(name)) {
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
}
