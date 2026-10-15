/// Qualifies a binding when several bindings share a type.
///
/// On an `Injectable` class or a `Provides` method it names the binding; on a
/// constructor or method parameter it selects the binding to inject; on a
/// route parameter that comes from the call scope it selects the value set
/// under that name.
///
/// ```dart
/// @Injectable()
/// @Named('primary')
/// final class PrimaryDb implements Database {}
/// ```
final class Named {
  /// Creates the annotation for [name].
  const Named(this.name);

  /// The qualifier; the `name` of the `Key`.
  final String name;
}
