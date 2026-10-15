/// Base class of user metadata attached to a controller or a route and read
/// with `ExecutionContext.metadata<T>()`; route metadata overrides
/// controller metadata.
///
/// The generator copies the annotation into the explicit `metadata` list,
/// so a subclass needs a `const` constructor whose parameters initialize
/// fields of the same name (`this.names` or `super.x`).
///
/// ```dart
/// final class Roles extends RouteMetadata {
///   const Roles(this.names);
///   final List<String> names;
/// }
///
/// @Post()
/// @Roles(['admin'])
/// User create(@Body() CreateUserDto dto) => ...;
/// ```
abstract class RouteMetadata {
  /// Creates the metadata.
  const RouteMetadata();
}
