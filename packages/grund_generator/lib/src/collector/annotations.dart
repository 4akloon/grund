import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Reads `package:grund_annotations` annotations from elements.
///
/// Annotations are matched by class name and library, not by type, so the
/// generator does not depend on the annotations package.
abstract final class Annotations {
  /// URI prefix of the annotations package.
  static const packageUri = 'package:grund_annotations/';

  /// The value of the first annotation on [element] whose class is [name]
  /// from the annotations package.
  static DartObject? find(Element element, String name) =>
      all(element, {name}).firstOrNull;

  /// The values of every annotation on [element] whose class is one of
  /// [names] from the annotations package, in source order.
  static List<DartObject> all(Element element, Set<String> names) => [
    for (final value in _values(element))
      if (isAnnotation(value.type, names)) value,
  ];

  /// Whether [type] is one of the classes [names] of the annotations
  /// package.
  static bool isAnnotation(DartType? type, Set<String> names) =>
      type is InterfaceType &&
      names.contains(type.element.name) &&
      '${type.element.library.uri}'.startsWith(packageUri);

  /// The `@Named` qualifier of [element], or `null`.
  static String? named(Element element) {
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

  static Iterable<DartObject> _values(Element element) sync* {
    for (final annotation in element.metadata.annotations) {
      if (annotation.computeConstantValue() case final value?) yield value;
    }
  }
}
