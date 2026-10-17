import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/jaspr_setup.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/pages.dart';
import 'helpers/sites.dart';

const _clientId = 'static/client/main.client.dart.js';

final class _Fragment extends StatelessComponent {
  const _Fragment();

  @override
  Component build(BuildContext context) => p([Component.text('item')]);
}

final class _FragmentApi extends HttpApi {
  _FragmentApi(super.injector);

  @override
  List<Route> get routes => [
    Route.get('/frag', (c) => Fragments.respond(c, const _Fragment())),
  ];
}

final class _FragmentModule extends Module {
  const _FragmentModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<_FragmentApi>(_FragmentApi.new, dependsOn: const []),
  ];
}

// Jaspr's state is global to the isolate of a test file, hence a file of
// its own for a configured clientId.
void main() {
  setUpAll(() {
    Jaspr.initializeApp(options: const ServerOptions(clientId: _clientId));
    JasprSetup.ensureInitialized();
  });

  test('a page has the client script, a fragment has none', () async {
    final client = await startPublic(
      [homePage(const UrlPage())],
      modules: [const _FragmentModule()],
    );

    final page = await client.get('/');
    final fragment = await client.get('/frag');

    expect(page.text, contains('main.client.dart.js'));
    expect(fragment.text, contains('<p>item</p>'));
    expect(fragment.text, isNot(contains('main.client.dart.js')));
    expect(fragment.text, isNot(contains('<head')));
  });
}
