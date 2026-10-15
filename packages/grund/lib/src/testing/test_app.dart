import '../app/app.dart';
import '../di/binding.dart';
import '../di/injector.dart';
import '../di/module.dart';

/// An application for tests: the graph is built and validated and the
/// singletons exist, but no runner serves, so no port is opened.
final class TestApp {
  TestApp._(this.app);

  /// Starts [root] with [overrides] and no runner running.
  static Future<TestApp> start({
    required Module root,
    List<Binding<Object>> overrides = const [],
  }) async {
    final app = App(root: root, overrides: overrides);
    await app.start(only: const {});
    return TestApp._(app);
  }

  /// The started application.
  final App app;

  /// The injector of the root module.
  Injector get injector => app.container.root;

  /// Resolves a [T] visible to the root module.
  T call<T extends Object>([String? name]) => injector<T>(name);

  /// Closes the application.
  Future<void> close() => app.close();
}
