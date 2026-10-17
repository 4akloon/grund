/// Sources of a small application `site` in the explicit API: one Jaspr
/// page at `/` of a site that shows its version and the pid, served on the loopback
/// port of its first argument; it prints `listening on <port>`.
abstract final class SiteSources {
  /// The entry point.
  static const main = '''
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:site/site.dart';

Future<void> main(List<String> arguments) async {
  final port = int.parse(arguments.first);
  final app = App(
    root: const SiteModule(),
    overrides: [
      Singleton<HttpConfig>(
        (_) => HttpConfig(address: InternetAddress.loopbackIPv4, port: port),
        dependsOn: const [],
      ),
    ],
  );
  await app.start();
  print('listening on \$port');
}
''';

  /// `lib/site.dart`.
  static const site = '''
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart' hide Key;

final class SiteModule extends Module {
  const SiteModule();

  @override
  List<Module> get imports => const [
    HttpModule(),
    IoAdapterModule(),
    JasprModule(),
    HomeSiteModule(),
  ];
}

final class HomeSite extends PageSite {
  HomeSite(super.injector);
}

final class HomeSiteModule extends Module {
  const HomeSiteModule();

  @override
  List<Binding<Object>> get bindings => [
    ...Pages.site<HomeSite>(HomeSite.new),
    Pages.under<HomeSite>((_) => [Page('/', build: (_) => const HomePage())]),
  ];
}

final class HomePage extends StatelessComponent {
  const HomePage();

  @override
  Component build(BuildContext context) =>
      Document(body: p([Component.text('page v1 pid \$pid')]));
}
''';

  /// The files of the application.
  static const files = {'bin/main.dart': main, 'lib/site.dart': site};
}
