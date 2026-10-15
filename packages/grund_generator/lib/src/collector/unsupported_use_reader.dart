import 'package:analyzer/dart/element/element.dart';

import '../construct/construct_annotations.dart';
import '../model/unsupported_use.dart';
import 'annotations.dart';
import 'source_locations.dart';

/// Finds uses of the annotations the generator reads that it cannot
/// honour, so that nothing is dropped silently.
final class UnsupportedUseReader {
  /// Creates the reader of the uses of [annotations].
  UnsupportedUseReader(this.locations, this.annotations)
    : _source = Annotations(annotations.libraries);

  /// Locations of declarations.
  final SourceLocations locations;

  /// The annotations the generator reads.
  final ConstructAnnotations annotations;

  final Annotations _source;

  /// The unsupported uses in [library]: class annotations on mixins,
  /// enums, extension types and extensions, and in every class unresolved
  /// annotations and annotated members it inherits.
  List<UnsupportedUse> read(LibraryElement library) => [
    for (final element in <Element>[
      ...library.mixins,
      ...library.enums,
      ...library.extensionTypes,
      ...library.extensions,
    ])
      ..._misplaced(element),
    for (final element in library.classes) ...[
      ..._unresolved(element),
      for (final method in element.methods) ..._unresolved(method),
      ..._inherited(element),
    ],
  ];

  Iterable<UnsupportedUse> _misplaced(Element element) sync* {
    final classAnnotations = annotations.classes.keys.toSet();
    for (final annotation in _source.all(element, classAnnotations)) {
      final name = annotation.type?.element?.name;
      yield _use(
        element,
        '@$name is only read on a class; ${element.kind.displayName} '
        '${element.displayName} is ignored.',
      );
    }
  }

  Iterable<UnsupportedUse> _unresolved(Element element) sync* {
    for (final name in _source.unresolved(element, annotations.names)) {
      yield _use(
        element,
        'An argument of @$name on ${element.displayName} is not a constant '
        'the generator can evaluate.',
      );
    }
  }

  Iterable<UnsupportedUse> _inherited(ClassElement element) sync* {
    final names = {
      for (final MapEntry(key: name, value: members)
          in annotations.classes.entries)
        if (_source.find(element, name) != null) ...members,
    };
    if (names.isEmpty) return;
    for (final supertype in element.allSupertypes) {
      for (final method in supertype.element.methods) {
        if (_source.all(method, names).isEmpty) continue;
        yield _use(
          element,
          '${supertype.element.displayName}.${method.displayName} is '
          'annotated but inherited by ${element.displayName}; grund reads '
          'only members declared in the class itself.',
        );
      }
    }
  }

  UnsupportedUse _use(Element element, String reason) => UnsupportedUse(
    element: element.displayName,
    reason: reason,
    location: locations.of(element),
  );
}
