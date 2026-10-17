import 'dart:io';

import 'package:grund/grund.dart';

import 'jaspr_config.dart';
import 'jaspr_setup.dart';
import 'live_reload_script.dart';
import 'page/non_page_requests.dart';
import 'page/page_renderer.dart';
import 'site/page_registry.dart';
import 'site/pages_runner.dart';
import 'site/site_validator.dart';
import 'site/static_api.dart';
import 'site/static_files.dart';

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
    Singleton<SiteValidator>((_) => const SiteValidator(), dependsOn: const []),
    Singleton<PagesRunner>(
      (i) => PagesRunner(i<PageRegistry>(), i<SiteValidator>()),
      dependsOn: const [Key<PageRegistry>(), Key<SiteValidator>()],
    ),
    Singleton<StaticFiles>(
      (i) => StaticFiles(i<JasprConfig>().staticDirectory),
      dependsOn: const [Key<JasprConfig>()],
    ),
    Singleton<NonPageRequests>(
      (i) => NonPageRequests(i<JasprConfig>()),
      dependsOn: const [Key<JasprConfig>()],
    ),
    Singleton<StaticApi>(
      (i) => StaticApi(
        i,
        i<JasprConfig>(),
        i<StaticFiles>(),
        i<NonPageRequests>(),
      ),
      dependsOn: const [
        Key<JasprConfig>(),
        Key<StaticFiles>(),
        Key<NonPageRequests>(),
      ],
    ),
  ];

  @override
  List<Object> get exports => const [
    Key<JasprConfig>(),
    Key<PageRenderer>(),
    Key<PageRegistry>(),
    Key<NonPageRequests>(),
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
