import 'package:grund/grund.dart';

import '../hook/hook_ref.dart';
import '../hook/http_hook.dart';
import 'route.dart';

/// A group of routes under one path prefix.
///
/// Bind an `HttpApi` subclass as a singleton in a module; every `HttpApi` of
/// the application is served by the `HttpServer`. The explicit form and the
/// code the generator emits for an annotated API class are the same thing:
///
/// ```dart
/// final class UsersApi extends HttpApi {
///   UsersApi(super.injector, this._users);
///   final UsersService _users;
///
///   @override String get path => '/users';
///   @override List<Route> get routes => [
///     Route.get('/:id', (c) => _users.find(c.path.integer('id'))),
///   ];
/// }
/// ```
abstract base class HttpApi {
  /// Creates the API over the [injector] of the module that declares it.
  HttpApi(this.injector);

  /// The injector of the declaring module: hooks are resolved from it and a
  /// call scope is opened on it for every request, so handlers and hooks see
  /// what that module sees.
  final Injector injector;

  /// The prefix of every route; empty for none.
  String get path => '';

  /// Hooks that wrap every route of the API, after the global ones.
  List<HookRef<HttpHook>> get use => const [];

  /// The routes.
  ///
  /// Return a new list on every call: the server reads it again after a hot
  /// reload and so sees the edited handlers.
  List<Route> get routes;
}
