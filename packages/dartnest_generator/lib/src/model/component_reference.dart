import 'type_model.dart';

/// A type listed in `@UseGuards`, `@UseInterceptors`, `@UsePipes` or
/// `@UseFilters`.
final class ComponentReference {
  /// Creates the reference.
  const ComponentReference(this.type, {required this.isValid});

  /// The component class.
  final TypeModel type;

  /// Whether the class is a component of the kind its annotation needs (a
  /// `Guard` for `@UseGuards`, ...).
  final bool isValid;
}
