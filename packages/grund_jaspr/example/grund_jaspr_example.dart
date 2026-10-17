import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart' hide Key;

/// Counts the pages served; one instance for the application.
final class VisitCounter {
  int _visits = 0;

  /// Counts one more visit and returns the total.
  int visit() => ++_visits;
}

/// Exports [VisitCounter] to the pages.
final class CounterModule extends Module {
  /// Creates the module.
  const CounterModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<VisitCounter>((_) => VisitCounter(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<VisitCounter>()];
}

/// The page: the visit count, read from DI.
final class HomePage extends StatelessComponent {
  /// Creates the page.
  const HomePage();

  @override
  Component build(BuildContext context) => Document(
    title: 'grund_jaspr',
    body: p([
      Component.text('Visit number ${context.call<VisitCounter>().visit()}.'),
    ]),
  );
}

/// The one site of the example: no prefix, no hooks.
final class WebSite extends PageSite {
  /// Creates the site.
  WebSite(super.injector);
}

/// Declares [WebSite] and its only page, which counts visits.
final class WebModule extends Module {
  /// Creates the module.
  const WebModule();

  @override
  List<Module> get imports => const [CounterModule()];

  @override
  List<Binding<Object>> get bindings => [
    ...Pages.site<WebSite>(WebSite.new),
    Pages.under<WebSite>((_) => [Page('/', build: (_) => const HomePage())]),
  ];
}

/// The root module: the HTTP server over dart:io and the pages.
final class AppModule extends Module {
  /// Creates the module.
  const AppModule();

  @override
  List<Module> get imports => const [
    HttpModule(),
    IoAdapterModule(),
    JasprModule(),
    WebModule(),
  ];
}

/// Renders `GET /` twice in process and returns the two paragraphs.
Future<List<String>> renderTwice() async {
  final app = await TestApp.start(root: const AppModule());
  try {
    final client = TestClient.of(app);
    return [
      for (var visit = 0; visit < 2; visit++)
        RegExp('<p>(.*)</p>').firstMatch((await client.get('/')).text)?[1] ??
            '',
    ];
  } finally {
    await app.close();
  }
}

/// Serves the page on port 8080 until Ctrl+C.
Future<void> main() => App(root: const AppModule()).run();
