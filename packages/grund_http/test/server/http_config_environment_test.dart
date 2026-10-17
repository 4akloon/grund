import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/fake_adapter.dart';
import '../helpers/adapter_module.dart';

Environment _env(Map<String, String> values) => Environment(values);

Matcher _invalid(String name) =>
    throwsA(isA<InvalidVariableError>().having((e) => e.name, 'name', name));

final class _Root extends Module {
  _Root(this._imports);
  final List<Module> _imports;
  @override
  List<Module> get imports => _imports;
}

Binding<Object> _environment(Map<String, String> values) =>
    Singleton<Environment>((_) => _env(values), dependsOn: const []);

void main() {
  group('HttpConfig.fromEnvironment', () {
    test('keeps the defaults when nothing is set', () {
      const defaults = HttpConfig(
        address: 'a',
        port: 5,
        maxBodyBytes: 9,
        debug: true,
        accessLog: false,
      );
      final config = HttpConfig.fromEnvironment(_env({}), defaults: defaults);

      expect(config.address, 'a');
      expect(config.port, 5);
      expect(config.maxBodyBytes, 9);
      expect(config.debug, isTrue);
      expect(config.accessLog, isFalse);
    });

    test('reads the address and the port', () {
      final config = HttpConfig.fromEnvironment(
        _env({'HOST': '0.0.0.0', 'PORT': '9000'}),
      );

      expect(config.address, '0.0.0.0');
      expect(config.port, 9000);
    });

    test('leaves the other fields to the defaults', () {
      final config = HttpConfig.fromEnvironment(
        _env({'PORT': '1'}),
        defaults: const HttpConfig(maxBodyBytes: 7, debug: true),
      );

      expect(config.maxBodyBytes, 7);
      expect(config.debug, isTrue);
    });

    test('accepts the port 0 and 65535', () {
      expect(HttpConfig.fromEnvironment(_env({'PORT': '0'})).port, 0);
      expect(HttpConfig.fromEnvironment(_env({'PORT': '65535'})).port, 65535);
    });

    for (final port in ['65536', '-1', 'abc', '', ' 80']) {
      test('rejects the port "$port"', () {
        expect(
          () => HttpConfig.fromEnvironment(_env({'PORT': port})),
          _invalid('PORT'),
        );
      });
    }

    for (final host in ['', 'a b', ' h', 'h\t']) {
      test('rejects the host "${host.replaceAll('\t', r'\t')}"', () {
        expect(
          () => HttpConfig.fromEnvironment(_env({'HOST': host})),
          throwsA(
            isA<InvalidVariableError>()
                .having((e) => e.name, 'name', 'HOST')
                .having(
                  (e) => e.expected,
                  'expected',
                  'a host name or an IP address',
                ),
          ),
        );
      });
    }
  });

  group('HttpModule.fromEnvironment', () {
    late FakeAdapter adapter;

    setUp(() => adapter = FakeAdapter());

    App appWith(HttpModule http, Map<String, String> values) => App(
      root: _Root([const EnvironmentModule(), http, AdapterModule(adapter)]),
      overrides: [_environment(values)],
    );

    test('listens on HOST and PORT', () async {
      final app = appWith(const HttpModule.fromEnvironment(), {
        'HOST': '127.0.0.1',
        'PORT': '0',
      });
      await app.start();
      addTearDown(app.close);

      expect(adapter.address, '127.0.0.1');
      expect(adapter.port, 0);
    });

    test('uses the defaults for what is unset', () async {
      final app = appWith(
        const HttpModule.fromEnvironment(
          defaults: HttpConfig(address: 'h', port: 7),
        ),
        {'PORT': '8'},
      );
      await app.start();
      addTearDown(app.close);

      expect(adapter.address, 'h');
      expect(adapter.port, 8);
    });

    test('a plain HttpModule ignores PORT', () async {
      final app = appWith(
        const HttpModule(config: HttpConfig(address: 'h', port: 7)),
        {'PORT': '9', 'HOST': 'other'},
      );
      await app.start();
      addTearDown(app.close);

      expect(adapter.address, 'h');
      expect(adapter.port, 7);
    });

    test('a bad PORT fails the start before the adapter listens', () async {
      final app = appWith(const HttpModule.fromEnvironment(), {'PORT': 'x'});

      await expectLater(app.start(), _invalid('PORT'));
      expect(adapter.listenCalls, 0);
    });

    test('without EnvironmentModule the graph lacks Environment', () async {
      final app = App(
        root: _Root([
          const HttpModule.fromEnvironment(),
          AdapterModule(adapter),
        ]),
      );

      await expectLater(app.start(), throwsA(isA<MissingProviderError>()));
      expect(adapter.listenCalls, 0);
    });
  });
}
