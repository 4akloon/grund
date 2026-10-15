import 'package:analyzer/dart/element/element.dart';

import 'source_locations.dart';

/// What a construct reads its own annotations from (`Construct.collect`).
final class CollectionContext {
  /// Creates the context.
  const CollectionContext({
    required this.packageName,
    required this.libraries,
    required this.locations,
  });

  /// The package being generated.
  final String packageName;

  /// The resolved libraries of the package's `lib/`, without generated
  /// ones, in library-URI order.
  final List<LibraryElement> libraries;

  /// Turns elements into locations relative to the package root.
  final SourceLocations locations;
}
