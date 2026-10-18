import 'dart:convert';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:test/test.dart';

import 'helpers/client_samples.dart';
import 'helpers/sites.dart';

const _withClients = JasprConfig(
  clients: ClientComponents([ClientComponent<Plain>('plain', decode: _plain)]),
);

const _otherStatic = JasprConfig(
  staticPath: '/assets',
  clients: ClientComponents([ClientComponent<Plain>('plain', decode: _plain)]),
);

Plain _plain(Map<String, Object?> _) => const Plain();

final class _Root extends Module {
  const _Root(this._config);

  final JasprConfig Function() _config;

  @override
  List<Module> get imports => [
    const HttpModule(config: HttpConfig(address: '127.0.0.1', port: 0)),
    const IoAdapterModule(),
    JasprModule(config: _config()),
    PublicPagesModule([homePage(const Plain())]),
  ];
}

void main() {
  setUp(Jaspr.initializeApp);
  tearDown(Jaspr.initializeApp);

  Future<App> start(JasprConfig Function() config) async {
    final app = App(root: _Root(config));
    await app.start();
    addTearDown(app.close);
    return app;
  }

  Future<String> page(App app) async {
    final port = (app.container.root<HttpAdapter>() as IoAdapter).port;
    final client = HttpClient();
    try {
      final request = await client.get('127.0.0.1', port, '/');
      final response = await request.close();
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  test('the options survive a reassemble', () async {
    var config = _withClients;
    final app = await start(() => config);
    expect(await page(app), contains('main.client.dart.js'));

    await app.reassemble();

    expect(await page(app), contains('main.client.dart.js'));
  });

  test('the options of the newer application outlive the older one', () async {
    final older = await start(() => _withClients);
    final newer = await start(() => _otherStatic);

    await older.close();

    expect(Jaspr.options.clientId, 'assets/client/main.client.dart.js');
    expect(await page(newer), contains('assets/client/main.client.dart.js'));
  });

  test('a newer application without clients is not given the options of '
      'the older one when that one closes last', () async {
    final older = await start(() => _withClients);
    final newer = await start(JasprConfig.new);

    await older.close();

    expect(Jaspr.options.clientId, isNull);
    expect(await page(newer), isNot(contains('main.client.dart.js')));
  });
}
