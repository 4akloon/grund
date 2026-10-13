/// Declares a controller; the generator writes a function that returns the
/// explicit `Controller` (`UsersController` → `usersController()`).
///
/// The instance is created through the unnamed constructor with the same
/// rules as an `Injectable`. Methods annotated with `Get`, `Post`, `Put`,
/// `Patch` or `Delete` become routes.
///
/// ```dart
/// @Controller('/users')
/// class UsersController {
///   UsersController(this.service);
///   final UsersService service;
///
///   @Get('/:id')
///   User findOne(@Param('id') int id) => service.find(id);
/// }
/// ```
final class Controller {
  /// Creates the annotation with the path prefix of every route.
  const Controller([this.path = '']);

  /// Path prefix of every route.
  final String path;
}
