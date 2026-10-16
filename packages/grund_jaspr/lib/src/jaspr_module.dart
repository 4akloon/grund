import 'dart:io';

import 'package:grund/grund.dart';
import 'package:jaspr/server.dart';

import 'jaspr_config.dart';
import 'jaspr_pages.dart';
import 'jaspr_setup.dart';
import 'live_reload_script.dart';

/// Server-side rendered pages of the Jaspr component [app], served by the
/// application's `HttpModule` next to its APIs.
///
/// ```dart
/// final class AppModule extends Module {
///   const AppModule();
///
///   @override
///   List<Module> get imports => const [
///     HttpModule(),
///     IoAdapterModule(),
///     JasprModule(app: HomePage.new, imports: [TasksModule()]),
///   ];
/// }
/// ```
///
/// It does not import `HttpModule`: the application imports it once, with
/// its own hooks and configuration. Pages see the exports of [imports] and
/// of global modules through `context.call<T>()`.
final class JasprModule extends Module {
  /// Serves [app] with [config]; components see the exports of [imports].
  const JasprModule({
    required this.app,
    this.imports = const [],
    this.config = const JasprConfig(),
  });

  /// Builds the root component of a page; called for every request.
  final Component Function() app;

  @override
  final List<Module> imports;

  /// The static directory, the page suffixes and the live reload URL.
  final JasprConfig config;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<JasprPages>(
      (i) => JasprPages(i, app: app, config: _withEnvironment()),
      dependsOn: const [],
    ),
  ];

  @override
  void onInit(Injector injector) => JasprSetup.ensureInitialized();

  JasprConfig _withEnvironment() => config.liveReloadUrl != null
      ? config
      : config.withLiveReloadUrl(
          LiveReloadScript.urlFrom(Platform.environment),
        );
}
