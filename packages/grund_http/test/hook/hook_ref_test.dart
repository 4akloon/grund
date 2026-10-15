import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

final class KeyHook extends HttpHook {
  const KeyHook([this.key = 'default']);

  final String key;
}

final class HooksModule extends Module {
  const HooksModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<KeyHook>((i) => const KeyHook('from graph'), dependsOn: const []),
  ];
}

final class BareModule extends Module {
  const BareModule();
}

void main() {
  group('HookRef', () {
    test('type() resolves the hook from the injector', () async {
      final app = await TestApp.start(root: const HooksModule());
      addTearDown(app.close);

      final hook = const HookRef<KeyHook>.type().resolve(app.injector);

      expect(hook.key, 'from graph');
    });

    test('instance() is the value itself, no injector needed', () async {
      final app = await TestApp.start(root: const BareModule());
      addTearDown(app.close);
      const given = KeyHook('given');

      expect(
        const HookRef<KeyHook>.instance(given).resolve(app.injector),
        same(given),
      );
    });

    test(
      'type() of a hook nobody provides is a MissingProviderError',
      () async {
        final app = await TestApp.start(root: const BareModule());
        addTearDown(app.close);

        expect(
          () => const HookRef<KeyHook>.type().resolve(app.injector),
          throwsA(isA<MissingProviderError>()),
        );
      },
    );

    test('resolve of a list keeps the order', () async {
      final app = await TestApp.start(root: const HooksModule());
      addTearDown(app.close);

      final chain = HookChain.resolve(const [
        HookRef<KeyHook>.instance(KeyHook('a')),
        HookRef<KeyHook>.type(),
      ], app.injector);

      expect(chain.hooks.map((h) => (h as KeyHook).key), ['a', 'from graph']);
    });
  });
}
