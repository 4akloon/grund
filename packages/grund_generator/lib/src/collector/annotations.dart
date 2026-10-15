import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Reads annotations from elements.
///
/// Annotations are matched by class name and library, not by type, so the
/// generator does not depend on the packages that declare them. Only the
/// libraries named by [libraryPrefixes] count: a class of the same name
/// from another library is not an annotation.
final class Annotations {
  /// Creates a reader of the annotations declared under [libraryPrefixes],
  /// URI prefixes such as `package:grund/src/annotations/`.
  const Annotations(this.libraryPrefixes);

  /// URI prefix of the dependency-injection annotations of `package:grund`.
  static const coreLibrary = 'package:grund/src/annotations/';

  /// The reader of the core annotations alone.
  static const core = Annotations({coreLibrary});

  /// The URI prefixes of the libraries whose classes are annotations.
  final Set<String> libraryPrefixes;

  /// The value of the first annotation on [element] whose class is [name]
  /// from the annotation libraries.
  DartObject? find(Element element, String name) =>
      all(element, {name}).firstOrNull;

  /// The values of every annotation on [element] whose class is one of
  /// [names] from the annotation libraries, in source order.
  List<DartObject> all(Element element, Set<String> names) => [
    for (final value in _values(element))
      if (isAnnotation(value.type, names)) value,
  ];

  /// The class names, among [names], of annotations on [element] whose
  /// constant value cannot be evaluated (an argument does not resolve).
  List<String> unresolved(Element element, Set<String> names) => [
    for (final annotation in element.metadata.annotations)
      if (annotation.computeConstantValue() == null)
        if (annotation.element case final ConstructorElement constructor)
          if (constructor.enclosingElement.name case final name?)
            if (names.contains(name) &&
                _isAnnotationLibrary(constructor.library))
              name,
  ];

  /// Whether [type] is one of the classes [names] of the annotation
  /// libraries.
  bool isAnnotation(DartType? type, Set<String> names) =>
      type is InterfaceType &&
      names.contains(type.element.name) &&
      _isAnnotationLibrary(type.element.library);

  /// The `@Named` qualifier of [element], or `null`.
  String? named(Element element) {
    final annotation = find(element, 'Named');
    return annotation == null
        ? null
        : field(annotation, 'name')?.toStringValue();
  }

  /// Field [name] of [object], looked up in its superclasses too.
  static DartObject? field(DartObject object, String name) {
    for (DartObject? current = object; current != null;) {
      final value = current.getField(name);
      if (value != null) return value;
      current = current.getField('(super)');
    }
    return null;
  }

  /// [entry] of an annotation list as a diagnostic shows it: a type or
  /// function by name, anything else as `a value of type T`.
  static String describe(DartObject entry) =>
      entry.toTypeValue()?.getDisplayString() ??
      entry.toFunctionValue()?.displayName ??
      'a value of type ${entry.type?.getDisplayString() ?? 'unknown'}';

  bool _isAnnotationLibrary(LibraryElement library) =>
      libraryPrefixes.any('${library.uri}'.startsWith);

  static Iterable<DartObject> _values(Element element) sync* {
    for (final annotation in element.metadata.annotations) {
      if (annotation.computeConstantValue() case final value?) yield value;
    }
  }
}
