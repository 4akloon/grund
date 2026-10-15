import 'package:grund/grund.dart';

import 'http_hook.dart';

/// A reference to a hook, as listed in `HttpModule(use:)`, `HttpApi.use` and
/// `Route.use`.
///
/// ```dart
/// const HookRef<ApiKeyHook>.type()                      // from the graph
/// const HookRef<RolesHook>.instance(RolesHook(Role.editor)) // a constant
/// ```
///
/// The hook type is a type argument because the graph is resolved by type
/// and a `Type` value cannot be turned into an instance without mirrors.
/// Keep the argument on `.instance` in a list typed `List<HookRef<HttpHook>>`:
/// without it the context infers `HttpHook` as [hookType].
///
/// In the annotations of `grund_http/annotations.dart` the wrapper is not
/// needed: `use: [ApiKeyHook, RolesHook(Role.editor)]` (a hook class, a const
/// instance) generates these references.
final class HookRef<T extends HttpHook> {
  /// Refers to the hook of type [T] that the module graph provides.
  const HookRef.type() : _instance = null;

  /// Refers to the constant [hook].
  const HookRef.instance(T hook) : _instance = hook;

  final T? _instance;

  /// The hook type, for messages.
  Type get hookType => T;

  /// The hook: the given instance, or [T] resolved from [injector] (a call
  /// scope, so `Scoped` and `Transient` hooks work).
  T resolve(Injector injector) => _instance ?? injector<T>();
}
