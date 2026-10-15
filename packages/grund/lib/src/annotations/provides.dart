import 'scope.dart';

/// Marks a `static` method of a `Module` class as a binding of its return
/// type.
///
/// The parameters are resolved like the constructor parameters of an
/// `Injectable`. A `Future<T>` result makes the binding asynchronous: the
/// singleton is awaited at startup. This is how runtime configuration enters
/// the graph.
///
/// ```dart
/// @Provides()
/// static TasksConfig config(AppConfig app) => TasksConfig(pageSize: app.pageSize);
/// ```
final class Provides {
  /// Creates the annotation with the [scope] of the binding.
  const Provides({this.scope = Scope.singleton});

  /// How long the instances live.
  final Scope scope;
}
