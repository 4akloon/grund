import 'package:analyzer/dart/element/element.dart';

import '../model/unsupported_use.dart';
import 'annotations.dart';
import 'route_reader.dart';
import 'source_locations.dart';

/// Finds annotations the generator does not read, so that nothing is
/// dropped silently.
final class UnsupportedUseReader {
  /// Creates the reader.
  UnsupportedUseReader(this.locations);

  /// Locations of declarations.
  final SourceLocations locations;

  static const _classAnnotations = {'Injectable', 'Module', 'Api'};

  static const _memberAnnotations = {'Provides', ...RouteReader.annotations};

  /// The unsupported uses in [library]: annotations on mixins, enums,
  /// extension types and extensions, and in every class unresolved
  /// annotations and inherited members of `@Api` and `@Module` classes.
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
    for (final annotation in Annotations.all(element, _classAnnotations)) {
      final name = annotation.type?.element?.name;
      yield _use(
        element,
        '@$name is only read on a class; ${element.kind.displayName} '
        '${element.displayName} is ignored.',
      );
    }
  }

  Iterable<UnsupportedUse> _unresolved(Element element) sync* {
    for (final name in Annotations.unresolved(element, {
      ..._classAnnotations,
      ..._memberAnnotations,
    })) {
      yield _use(
        element,
        'An argument of @$name on ${element.displayName} is not a constant '
        'the generator can evaluate.',
      );
    }
  }

  Iterable<UnsupportedUse> _inherited(ClassElement element) sync* {
    final isApi = Annotations.find(element, 'Api') != null;
    final isModule = Annotations.find(element, 'Module') != null;
    if (!isApi && !isModule) return;
    final names = isApi ? RouteReader.annotations : const {'Provides'};
    for (final supertype in element.allSupertypes) {
      for (final method in supertype.element.methods) {
        if (Annotations.all(method, names).isEmpty) continue;
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
