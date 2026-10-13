import '../pipeline/application_error.dart';
import '../di/errors.dart';
import '../di/injector.dart';
import '../pipeline/enhancers.dart';
import 'route.dart';

/// Creates a controller instance with the injector of its module.
typedef ControllerFactory<T> = T Function(Injector injector);

/// Non-generic view of a controller: what `Module.controllers` holds.
///
/// Non-generic for the same reason as `ProviderSpec`: a generic element type
/// would push `Object` into the inference of `Controller(...)` written in
/// the list literal.
sealed class ControllerSpec {
  /// Path prefix of every route.
  String get path;

  /// The controller class.
  Type get type;

  /// Controller-level pipeline components.
  Enhancers get enhancers;

  /// Controller-level metadata; route metadata overrides it.
  List<Object> get metadata;

  /// The routes, in declaration order.
  List<Route<Object>> get routes;

  /// Creates the instance; throws [ControllerCreationError] when the factory
  /// throws anything but a `DartnestError`.
  Object instantiate(Injector injector);
}

/// A controller: a class whose instance handles the requests of [routes].
///
/// The instance is created once at startup, after the providers of its
/// module, with that module's injector.
///
/// ```dart
/// final usersController = Controller<UsersController>(
///   path: '/users',
///   create: (i) => UsersController(i.get()),
///   enhancers: const Enhancers(guards: [Use<AuthGuard>()]),
///   routes: [
///     Route.get('/:id', (c, ctx) async => c.findOne(await ctx.param('id'))),
///   ],
/// );
/// ```
///
/// Write the type argument: `Controller<UsersController>(...)` lets the
/// route handlers infer `c`.
final class Controller<T extends Object> implements ControllerSpec {
  /// Creates a controller.
  Controller({
    this.path = '',
    required ControllerFactory<T> create,
    required this.routes,
    this.enhancers = Enhancers.none,
    this.metadata = const [],
  }) : _create = create;

  @override
  final String path;

  @override
  final List<Route<T>> routes;

  @override
  final Enhancers enhancers;

  @override
  final List<Object> metadata;

  final ControllerFactory<T> _create;

  @override
  Type get type => T;

  @override
  T instantiate(Injector injector) {
    // Factory boundary, like ModuleInjector: wrap any failure with the
    // controller and module, keep the cause and stack, never swallow.
    try {
      return _create(injector);
    } on Object catch (error, stackTrace) {
      if (error is DartnestError) rethrow;
      Error.throwWithStackTrace(
        ControllerCreationError(
          controllerType: T,
          moduleId: injector.moduleId,
          error: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  @override
  String toString() => 'Controller<$T>($path)';
}
