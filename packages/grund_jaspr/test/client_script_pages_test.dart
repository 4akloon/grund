import 'dart:convert';

import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/client_script_removal.dart';
import 'package:jaspr/server.dart' hide Key;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'helpers/client_samples.dart';
import 'helpers/pages_app.dart';
import 'helpers/sites.dart';
import 'helpers/temp_dir.dart';

const _bundle = 'main.client.dart.js';
const _clients = ClientComponents([
  ClientComponent<Counter>(
    'counter',
    encode: Counter.toParams,
    decode: Counter.fromParams,
  ),
  ClientComponent<Plain>('plain', decode: _plain),
]);

Plain _plain(Map<String, Object?> _) => const Plain();

final class _TitledPlain extends StatelessComponent {
  const _TitledPlain();

  @override
  Component build(BuildContext context) => const Component.fragment([
    Document.head(title: 'Hello'),
    Component.text('x'),
  ]);
}

final class _FragmentApi extends HttpApi {
  _FragmentApi(super.injector);

  @override
  List<Route> get routes => [
    Route.get('/frag', (c) => Fragments.respond(c, const Counter(1, 'f'))),
  ];
}

final class _FragmentModule extends Module {
  const _FragmentModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<_FragmentApi>(_FragmentApi.new, dependsOn: const []),
  ];
}

void main() {
  setUp(Jaspr.initializeApp);
  tearDown(Jaspr.initializeApp);

  group('the bundle script on a page', () {
    test('a page without an island has none, and keeps its head', () async {
      final client = await startPublic([
        homePage(const _TitledPlain()),
      ], config: const JasprConfig(clients: _clients));

      final html = (await client.get('/')).text;

      expect(html, isNot(contains(_bundle)));
      expect(html, contains('<title>Hello</title>'));
    });

    test(
      'a page with no head content has no script and no empty head',
      () async {
        final client = await startPublic([
          homePage(const LoudCounter(1, 'x')),
        ], config: const JasprConfig(clients: _clients));

        final html = (await client.get('/')).text;

        expect(html, isNot(contains('<script')));
        expect(html, isNot(contains('<head></head>')));
      },
    );

    test('an island without parameters keeps the script', () async {
      final client = await startPublic([
        homePage(const Plain()),
      ], config: const JasprConfig(clients: _clients));

      final html = (await client.get('/')).text;

      expect(html, contains('<!--@plain-->'));
      expect(html, contains(_bundle));
    });

    test('live reload stays when the bundle script goes', () async {
      final client = await startPublic(
        [homePage(const _TitledPlain())],
        config: JasprConfig(
          clients: _clients,
          liveReloadUrl: Uri.parse('http://127.0.0.1:9/events'),
        ),
      );

      final html = (await client.get('/')).text;

      expect(html, contains('EventSource'));
      expect(html, isNot(contains(_bundle)));
    });

    test('a fragment with an island has no script', () async {
      final client = await startPublic(
        [homePage(const Plain())],
        config: const JasprConfig(clients: _clients),
        modules: [const _FragmentModule()],
      );

      final html = (await client.get('/frag')).text;

      expect(html, contains('<!--@counter'));
      expect(html, isNot(contains(_bundle)));
      expect(html, startsWith('<'), reason: 'no blank line where the head was');
    });
  });

  group('ClientScriptRemoval.unlessIslands', () {
    test('keeps a response that is not bytes', () {
      Jaspr.initializeApp(options: const ServerOptions(clientId: 'a.js'));
      final response = HttpResponse(
        200,
        body: StreamBody(const Stream.empty()),
      );

      expect(ClientScriptRemoval.unlessIslands(response), same(response));
    });

    test('keeps the response when there is no client id', () {
      final response = HttpResponse(
        200,
        body: BytesBody(utf8.encode('<head></head>')),
      );

      expect(ClientScriptRemoval.unlessIslands(response), same(response));
    });
  });

  group('the missing bundle', () {
    late List<LogRecord> records;

    setUp(() {
      records = [];
      final subscription = Logger('grund.jaspr').onRecord.listen(records.add);
      addTearDown(subscription.cancel);
    });

    List<LogRecord> warnings() =>
        records.where((r) => r.level == Level.WARNING).toList();

    test('is a warning that names the file and grund bundle', () async {
      final temp = TempDir.create();

      await startPublic([
        homePage(const Plain()),
      ], config: JasprConfig(staticDirectory: temp.path, clients: _clients));

      expect(
        warnings().single.message,
        allOf(contains(_bundle), contains('grund bundle')),
      );
    });

    test('is not a warning when the file is there', () async {
      final temp = TempDir.create()..write('client/$_bundle', '//');

      await startPublic([
        homePage(const Plain()),
      ], config: JasprConfig(staticDirectory: temp.path, clients: _clients));

      expect(warnings(), isEmpty);
    });

    test('is not checked without clients', () async {
      await startPublic([homePage(const Plain())]);

      expect(warnings(), isEmpty);
    });

    test('is not checked for an empty list of clients', () async {
      final temp = TempDir.create();

      await startPublic(
        [homePage(const Plain())],
        config: JasprConfig(
          staticDirectory: temp.path,
          clients: const ClientComponents([]),
        ),
      );

      expect(warnings(), isEmpty);
    });
  });

  test('a second application without clients has no script', () async {
    final first = await StartedPagesApp.start([
      const JasprModule(config: JasprConfig(clients: _clients)),
      PublicPagesModule([homePage(const Plain())]),
    ]);
    expect((await TestClient.of(first).get('/')).text, contains(_bundle));
    await first.close();

    final second = await startPublic([homePage(const Plain())]);

    expect((await second.get('/')).text, isNot(contains(_bundle)));
  });
}
