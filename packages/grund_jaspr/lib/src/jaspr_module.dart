import 'dart:io';

import 'package:grund/grund.dart';

import 'jaspr_config.dart';
import 'jaspr_setup.dart';
import 'live_reload_script.dart';
import 'page/page_renderer.dart';
import 'site/page_registry.dart';

/// The rendering services of Jaspr pages: the configuration, the renderer
/// and the registry of declared sites.
///
/// Sites and pages are declared in the modules that own them with
/// `Pages.site` and `Pages.under`:
///
/// ```dart
/// final class AppModule extends Module {
///   const AppModule();
///
///   @override
///   List<Module> get imports => const [
///     HttpModule(),
///     IoAdapterModule(),
///     JasprModule(),
///     HomeModule(),
///   ];
/// }
/// ```
///
/// It does not import `HttpModule`: the application imports it once, with
/// its own hooks and configuration.
final class JasprModule extends Module {
  /// Serves pages with [config].
  const JasprModule({this.config = const JasprConfig()});

  /// The static directory, the page suffixes and the live reload URL.
  final JasprConfig config;

  @override
  bool get global => true;

  @override
  List<Binding<Object>> get bindings => [
    Singleton<JasprConfig>((_) => _withEnvironment(), dependsOn: const []),
    Singleton<PageRenderer>(
      (i) => PageRenderer(liveReloadUrl: i<JasprConfig>().liveReloadUrl),
      dependsOn: const [Key<JasprConfig>()],
    ),
    Singleton<PageRegistry>((_) => PageRegistry(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [
    Key<JasprConfig>(),
    Key<PageRenderer>(),
    Key<PageRegistry>(),
  ];

  @override
  void onInit(Injector injector) {
    config.validate();
    JasprSetup.ensureInitialized();
  }

  JasprConfig _withEnvironment() => config.liveReloadUrl != null
      ? config
      : config.withLiveReloadUrl(
          LiveReloadScript.urlFrom(Platform.environment),
        );
}
