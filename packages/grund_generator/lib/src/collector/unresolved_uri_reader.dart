import 'package:analyzer/dart/element/element.dart';

import '../model/unresolved_uri.dart';
import 'source_locations.dart';

/// Finds the directives of a library whose URI does not resolve, so that a
/// typo in an import cannot silently hide the annotations that import
/// provided.
final class UnresolvedUriReader {
  /// Creates the reader whose locations come from [locations].
  const UnresolvedUriReader(this.locations);

  /// Locations of directives.
  final SourceLocations locations;

  /// The unresolved directives of [library], in source order per kind.
  ///
  /// A URI of a file with a double extension (`x.g.dart`) is skipped: it is
  /// a file some generator writes, missing on a fresh checkout, and
  /// `import`ing or `part`ing it is how its host library is wired.
  List<UnresolvedUri> read(LibraryElement library) => [
    for (final fragment in library.fragments) ...[
      for (final directive in fragment.libraryImports)
        if (_unresolved(directive, 'import', directive.importKeywordOffset)
            case final found?)
          found,
      for (final directive in fragment.libraryExports)
        if (_unresolved(directive, 'export', directive.exportKeywordOffset)
            case final found?)
          found,
      for (final directive in fragment.partIncludes)
        if (_unresolved(directive, 'part', directive.partKeywordOffset)
            case final found?)
          found,
    ],
  ];

  UnresolvedUri? _unresolved(
    ElementDirective directive,
    String keyword,
    int offset,
  ) {
    final uri = directive.uri;
    // The analyzer resolves a missing file to a source that does not exist.
    if (uri is DirectiveUriWithSource && uri.source.exists()) return null;
    if (uri is! DirectiveUriWithRelativeUriString) return null;
    final written = uri.relativeUriString;
    if (_isGeneratedName(written)) return null;
    return UnresolvedUri(
      uri: written,
      directive: keyword,
      location: locations.at(directive.libraryFragment, offset),
    );
  }

  static bool _isGeneratedName(String uri) {
    final name = uri.split('/').last;
    return name.endsWith('.dart') && '.'.allMatches(name).length > 1;
  }
}
