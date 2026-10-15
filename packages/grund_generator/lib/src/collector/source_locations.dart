import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

import '../diagnostic/source_location.dart';

/// Turns elements into [SourceLocation]s relative to the package root.
final class SourceLocations {
  /// Creates the reader for the package at [packageRoot] (absolute path).
  SourceLocations(this.packageRoot);

  /// Absolute path of the package root.
  final String packageRoot;

  /// Where [element]'s name is declared. Files outside [packageRoot] are
  /// shown by library URI.
  SourceLocation of(Element element) {
    final library = element.library;
    if (library == null) {
      throw StateError('Element ${element.displayName} has no library.');
    }
    final fragment = element.firstFragment;
    final libraryFragment = fragment.libraryFragment;
    if (libraryFragment == null) {
      return SourceLocation('${library.uri}', 1, 1);
    }
    final offset = fragment.nameOffset ?? fragment.offset;
    final position = libraryFragment.lineInfo.getLocation(offset);
    return SourceLocation(
      _display(libraryFragment.source.fullName, library.uri),
      position.lineNumber,
      position.columnNumber,
    );
  }

  /// The position of [offset] in the file of [fragment].
  SourceLocation at(LibraryFragment fragment, int offset) {
    final position = fragment.lineInfo.getLocation(offset);
    return SourceLocation(
      _display(fragment.source.fullName, fragment.element.uri),
      position.lineNumber,
      position.columnNumber,
    );
  }

  /// The package-relative path of the file of [library] (the library URI
  /// outside [packageRoot]).
  String pathOf(LibraryElement library) =>
      _display(library.firstFragment.source.fullName, library.uri);

  String _display(String file, Uri libraryUri) {
    if (!p.isWithin(packageRoot, file)) return '$libraryUri';
    return p.posix.joinAll(p.split(p.relative(file, from: packageRoot)));
  }
}
