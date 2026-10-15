import 'package:analyzer/dart/element/element.dart';

/// The libraries of one package that a library reaches through imports and
/// exports: what a build step needs to check the modules of that library
/// against their graph.
abstract final class LibraryReach {
  /// [root] and every library of [package] reachable from it, sorted by
  /// library URI. Other packages are not followed: they generate their
  /// own files.
  static List<LibraryElement> within(String package, LibraryElement root) {
    final reached = <String, LibraryElement>{'${root.uri}': root};
    final pending = [root];
    while (pending.isNotEmpty) {
      for (final next in _neighbours(pending.removeLast())) {
        if (_isOf(package, next) && reached['${next.uri}'] == null) {
          reached['${next.uri}'] = next;
          pending.add(next);
        }
      }
    }
    return [for (final key in reached.keys.toList()..sort()) reached[key]!];
  }

  static Iterable<LibraryElement> _neighbours(LibraryElement library) sync* {
    for (final fragment in library.fragments) {
      for (final import in fragment.libraryImports) {
        if (import.importedLibrary case final imported?) yield imported;
      }
      for (final export in fragment.libraryExports) {
        if (export.exportedLibrary case final exported?) yield exported;
      }
    }
  }

  // A generated file of this build is not readable yet (the step that writes
  // it may run later or in parallel), though the import names it; it is
  // not a source, and the collector must not read it either.
  static bool _isOf(String package, LibraryElement library) =>
      library.uri.scheme == 'package' &&
      library.uri.pathSegments.first == package &&
      library.firstFragment.source.exists();
}
