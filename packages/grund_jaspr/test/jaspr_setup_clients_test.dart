import 'package:grund_jaspr/client_components.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:grund_jaspr/src/jaspr_setup.dart';
import 'package:jaspr/server.dart';
import 'package:test/test.dart';

import 'helpers/client_samples.dart';

const _withCounter = JasprConfig(
  clients: ClientComponents([
    ClientComponent<Counter>(
      'counter',
      encode: Counter.toParams,
      decode: Counter.fromParams,
    ),
  ]),
);
const _otherStatic = JasprConfig(
  staticPath: '/assets',
  clients: ClientComponents([
    ClientComponent<Counter>(
      'counter',
      encode: Counter.toParams,
      decode: Counter.fromParams,
    ),
  ]),
);

void main() {
  setUp(Jaspr.initializeApp);
  tearDown(Jaspr.initializeApp);

  test('installs the client id and a target for the component type', () {
    final installed = JasprSetup.initialize(_withCounter);

    expect(installed, isNotNull);
    expect(Jaspr.options, same(installed));
    expect(Jaspr.options.clientId, 'static/client/main.client.dart.js');
    expect(Jaspr.options.clients!.keys, [Counter]);
    expect(Jaspr.options.clients![Counter]!.name, 'counter');
  });

  test('replaces the default options', () {
    Jaspr.initializeApp();
    expect(JasprSetup.initialize(_withCounter), isNotNull);
  });

  test('replaces the options of an earlier initialize', () {
    JasprSetup.initialize(_withCounter);
    final second = JasprSetup.initialize(_otherStatic);

    expect(Jaspr.options, same(second));
    expect(Jaspr.options.clientId, 'assets/client/main.client.dart.js');
  });

  test('refuses foreign options with clients', () {
    Jaspr.initializeApp(
      options: ServerOptions(clients: {Counter: ClientTarget<Counter>('c')}),
    );

    expect(
      () => JasprSetup.initialize(_withCounter),
      throwsA(
        isA<JasprSetupError>().having(
          (e) => e.toString(),
          'message',
          contains('Jaspr.initializeApp'),
        ),
      ),
    );
  });

  test('refuses foreign options with a client id', () {
    Jaspr.initializeApp(options: const ServerOptions(clientId: 'x.js'));

    expect(
      () => JasprSetup.initialize(_withCounter),
      throwsA(isA<JasprSetupError>()),
    );
  });

  test('without clients leaves our options alone', () {
    final installed = JasprSetup.initialize(_withCounter);

    expect(JasprSetup.initialize(const JasprConfig()), isNull);
    expect(Jaspr.options, same(installed));
  });

  test('without clients initializes an uninitialized Jaspr', () {
    expect(JasprSetup.initialize(const JasprConfig()), isNull);
    expect(Jaspr.isInitialized, isTrue);
  });

  test('release gives back the default options', () {
    final installed = JasprSetup.initialize(_withCounter);

    JasprSetup.release(installed);

    expect(Jaspr.options.clientId, isNull);
    expect(Jaspr.options.clients, isNull);
  });

  test('release in hot reload order keeps the newer options', () {
    final a = JasprSetup.initialize(_withCounter);
    final b = JasprSetup.initialize(_otherStatic);

    JasprSetup.release(a);
    expect(Jaspr.options, same(b));

    JasprSetup.release(b);
    expect(Jaspr.options.clientId, isNull);
  });

  test('release does not touch foreign options', () {
    final installed = JasprSetup.initialize(_withCounter);
    const foreign = ServerOptions(clientId: 'x.js');
    Jaspr.initializeApp(options: foreign);

    JasprSetup.release(installed);

    expect(Jaspr.options, same(foreign));
  });

  test('release of null does nothing', () {
    const foreign = ServerOptions(clientId: 'x.js');
    Jaspr.initializeApp(options: foreign);

    JasprSetup.release(null);

    expect(Jaspr.options, same(foreign));
  });

  test('allowed path suffixes survive initialize and release', () {
    Jaspr.initializeApp(allowedPathSuffixes: ['html', 'md']);

    final installed = JasprSetup.initialize(_withCounter);
    expect(Jaspr.allowedPathSuffixes, ['html', 'md']);

    JasprSetup.release(installed);
    expect(Jaspr.allowedPathSuffixes, ['html', 'md']);
  });

  test('useIsolates is refused with and without clients', () {
    Jaspr.initializeApp(useIsolates: true);

    expect(
      () => JasprSetup.initialize(_withCounter),
      throwsA(isA<JasprSetupError>()),
    );
    expect(
      () => JasprSetup.initialize(const JasprConfig()),
      throwsA(isA<JasprSetupError>()),
    );
  });
}
