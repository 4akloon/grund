import 'package:analyzer/dart/element/element.dart';

import '../model/unresolved_uri.dart';
import 'source_locations.dart';

/// Finds the directives of a library whose URI does not resolve, so that a
/// typo in an import cannot silently hide the annotations that import
/// provided.
final class UnresolvedUriReader {
  /// Creates the reader of the libraries of [packageName] whose locations
  /// come from [locations].
  const UnresolvedUriReader(this.packageName, this.locations);

  /// The package being generated: its own outputs may be missing.
  final String packageName;

  /// Locations of directives.
  final SourceLocations locations;

  /// The unresolved directives of [library], in source order per kind.
  ///
  /// A relative URI or a `package:` URI of [packageName] of a file with a
  /// double extension (`x.g.dart`) is skipped: it is a file some generator
  /// writes, missing on a fresh checkout, and `import`ing or `part`ing it is
  /// how its host library is wired. The same name in another package, or
  /// behind any other scheme, is a typo.
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
    if (_isOwnGeneratedFile(written)) return null;
    return UnresolvedUri(
      uri: written,
      directive: keyword,
      location: locations.at(directive.libraryFragment, offset),
    );
  }

  bool _isOwnGeneratedFile(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return false;
    final isOwn = switch (parsed.scheme) {
      '' => true,
      'package' =>
        parsed.pathSegments.isNotEmpty &&
            parsed.pathSegments.first == packageName,
      _ => false,
    };
    if (!isOwn) return false;
    final name = parsed.pathSegments.lastOrNull ?? '';
    return name.endsWith('.dart') && '.'.allMatches(name).length > 1;
  }
}
