import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_io/grund_io.dart';
import 'package:test/test.dart';

/// The root: imports the adapter module under test and the consumer.
final class _Root extends Module {
  const _Root(this.adapter);

  final IoAdapterModule adapter;

  @override
  List<Module> get imports => [adapter, const _Consumer()];
}

/// Resolves the adapter although it does not import its module.
final class _Consumer extends Module {
  const _Consumer();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<String>(
      (i) => i<HttpAdapter>().runtimeType.toString(),
      dependsOn: const [Key<HttpAdapter>()],
    ),
  ];

  @override
  List<Object> get exports => const [Key<String>()];
}

Future<TestApp> _start([IoAdapterModule adapter = const IoAdapterModule()]) =>
    TestApp.start(root: _Root(adapter));

void main() {
  group('IoAdapterModule', () {
    test('binds an IoAdapter as the HttpAdapter', () async {
      final app = await _start();
      addTearDown(app.close);

      expect(app<HttpAdapter>(), isA<IoAdapter>());
    });

    test('is global: a module that does not import it resolves it', () async {
      final app = await _start();
      addTearDown(app.close);

      expect(app<String>(), 'IoAdapter');
    });

    test('creates one adapter per application', () async {
      final app = await _start();
      addTearDown(app.close);

      expect(identical(app<HttpAdapter>(), app<HttpAdapter>()), isTrue);
    });

    test('hands closeTimeout and onError to the adapter', () async {
      void onError(Object error, StackTrace stackTrace) {}
      final app = await _start(
        IoAdapterModule(
          closeTimeout: const Duration(seconds: 3),
          onError: onError,
        ),
      );
      addTearDown(app.close);

      expect(
        app<HttpAdapter>(),
        isA<IoAdapter>()
            .having(
              (a) => a.closeTimeout,
              'closeTimeout',
              const Duration(seconds: 3),
            )
            .having((a) => a.onError, 'onError', same(onError)),
      );
    });

    test('keeps the defaults of the adapter without arguments', () async {
      final app = await _start();
      addTearDown(app.close);

      expect(
        app<HttpAdapter>(),
        isA<IoAdapter>()
            .having(
              (a) => a.closeTimeout,
              'closeTimeout',
              IoAdapter.defaultCloseTimeout,
            )
            .having((a) => a.onError, 'onError', same(IoAdapter.printError)),
      );
    });
  });
}
