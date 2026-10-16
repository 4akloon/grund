import 'package:analyzer/dart/element/element.dart';

import '../model/public_imports.dart';

/// Finds, for the declarations of other packages' `src/` libraries that a
/// source library can see, a public library of that package to import
/// instead, so generated code does not depend on a package's private layout
/// (the `implementation_imports` lint).
abstract final class PublicImportsReader {
  /// The table of [host], a library of package [packageName]: only the
  /// public libraries [host] imports itself are candidates, the shortest
  /// URI first, then in URI order. The `src/` of [packageName] is the
  /// user's own and stays as it is.
  static PublicImports read(LibraryElement host, String packageName) {
    final candidates = <(String, LibraryImport)>[
      for (final fragment in host.fragments)
        for (final directive in fragment.libraryImports)
          if (directive.importedLibrary case final library?)
            if (_isPublic(library.uri)) ('${library.uri}', directive),
    ]..sort((a, b) => _byLength(a.$1, b.$1));
    final uris = <String, String>{};
    for (final (uri, directive) in candidates) {
      final library = directive.importedLibrary;
      if (library == null) continue;
      final names = library.exportNamespace.definedNames2;
      for (final MapEntry(key: name, value: element) in names.entries) {
        final declaring = element.library?.uri;
        if (declaring == null || name.endsWith('=')) continue;
        if (!_isOtherPackageSource(declaring, packageName)) continue;
        if (!_isVisible(name, directive.combinators)) continue;
        uris.putIfAbsent(PublicImports.key('$declaring', name), () => uri);
      }
    }
    return PublicImports(uris);
  }

  /// Whether the import's `show` and `hide` clauses let [name] through.
  static bool _isVisible(String name, List<NamespaceCombinator> combinators) =>
      combinators.every(
        (combinator) => switch (combinator) {
          ShowElementCombinator(:final shownNames) => shownNames.contains(name),
          HideElementCombinator(:final hiddenNames) => !hiddenNames.contains(
            name,
          ),
        },
      );

  static int _byLength(String a, String b) =>
      a.length != b.length ? a.length - b.length : a.compareTo(b);

  static bool _isPublic(Uri uri) =>
      uri.scheme == 'package' &&
      uri.pathSegments.length > 1 &&
      uri.pathSegments[1] != 'src';

  static bool _isOtherPackageSource(Uri uri, String package) =>
      uri.scheme == 'package' &&
      uri.pathSegments.length > 2 &&
      uri.pathSegments[1] == 'src' &&
      uri.pathSegments.first != package;
}
