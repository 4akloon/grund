/// The `package:grund_annotations` classes a construct reads, by class
/// name.
///
/// The collector uses them for what every construct needs: it reports a
/// misplaced, inherited or unevaluable use of them as `unsupported_use`,
/// and it collects a class carrying one of [injectable] as an injectable.
final class ConstructAnnotations {
  /// Creates the set.
  const ConstructAnnotations({
    this.classes = const {},
    this.injectable = const {},
  });

  /// The annotations read on a class, each with the names of the
  /// annotations read on the methods declared in that class; an annotated
  /// method a class inherits is reported, never read.
  final Map<String, Set<String>> classes;

  /// The names, among [classes], of annotations that make dependency
  /// injection create the class, as `@Injectable` does.
  final Set<String> injectable;

  /// The names of every class and method annotation.
  Set<String> get names => {
    ...classes.keys,
    for (final members in classes.values) ...members,
  };

  /// This set and [other] together.
  ConstructAnnotations union(ConstructAnnotations other) =>
      ConstructAnnotations(
        classes: {
          for (final name in {...classes.keys, ...other.classes.keys})
            name: {...?classes[name], ...?other.classes[name]},
        },
        injectable: {...injectable, ...other.injectable},
      );
}
