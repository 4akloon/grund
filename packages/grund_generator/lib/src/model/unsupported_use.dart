import '../diagnostic/source_location.dart';

/// An annotation the generator cannot honour: it sits on an element kind or
/// member the generator does not read, or has an argument that does not
/// evaluate.
final class UnsupportedUse {
  /// Creates the model.
  const UnsupportedUse({
    required this.element,
    required this.reason,
    required this.location,
  });

  /// The name of the annotated element, such as `UsersModule` or `Base.create`.
  final String element;

  /// Why the use is unsupported, as a sentence.
  final String reason;

  /// Where the annotated class or declaration is.
  final SourceLocation location;
}
