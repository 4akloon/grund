import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/container.dart';
import 'package:grund/src/di/key.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/errors/graph_errors.dart';
import 'package:grund/src/errors/resolution_errors.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';
import '../helpers/tracked.dart';

Future<Container> start(List<Binding<Object>> bindings) =>
    Container.create(ModuleGraph.build(AppModule(bindings: bindings)));

void main() {
  group('Call scopes', () {
    test('a scoped binding is one instance per call', () async {
      final container = await start([
        Scoped<Clock>((i) => Clock(), dependsOn: const []),
      ]);

      final first = container.root.openCall();
      final second = container.root.openCall();

      expect(first<Clock>(), same(first<Clock>()));
      expect(first<Clock>(), isNot(same(second<Clock>())));
    });

    test('a scoped binding cannot be resolved outside a call', () async {
      final container = await start([
        Scoped<Clock>((i) => Clock(), dependsOn: const []),
      ]);

      expect(
        () => container.root<Clock>(),
        throwsA(
          isA<ScopedOutsideCallError>().having(
            (e) => e.key,
            'key',
            const Key<Clock>(),
          ),
        ),
      );
    });

    test(
      'closing a call disposes its scoped instances in reverse order',
      () async {
        final log = <String>[];
        final container = await start([
          Scoped<Tracked>(
            (i) => Tracked('first', log),
            name: 'first',
            dependsOn: const [],
          ),
          Scoped<Tracked>(
            (i) => Tracked('second', log),
            name: 'second',
            dependsOn: const [],
          ),
        ]);
        final call = container.root.openCall();
        call<Tracked>('first');
        call<Tracked>('second');

        await call.close();
        await call.close();

        expect(log, ['dispose second', 'dispose first']);
      },
    );

    test('closing a call collects every failure of its disposals', () async {
      final log = <String>[];
      final container = await start([
        Scoped<Tracked>(
          (i) => Tracked('a', log, failure: StateError('a')),
          name: 'a',
          dependsOn: const [],
        ),
        Scoped<Tracked>(
          (i) => Tracked('b', log, failure: StateError('b')),
          name: 'b',
          dependsOn: const [],
        ),
      ]);
      final call = container.root.openCall();
      call<Tracked>('a');
      call<Tracked>('b');

      await expectLater(
        call.close(),
        throwsA(
          isA<ShutdownError>().having(
            (e) => e.failures,
            'failures',
            hasLength(2),
          ),
        ),
      );
      expect(log, ['dispose b', 'dispose a']);
    });

    // RF-2: calls that overlap in time never share state.
    test('calls that overlap keep their values and instances apart', () async {
      final container = await start([
        Scoped<Clock>((i) => Clock(), dependsOn: const []),
      ]);

      Future<(Clock, Secret)> serve(Secret secret, int delayMs) async {
        final call = container.root.openCall();
        call.set<Secret>(secret);
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        return (call<Clock>(), call<Secret>());
      }

      final first = Secret();
      final second = Secret();
      final results = await Future.wait([serve(first, 20), serve(second, 1)]);

      expect(results[0].$2, same(first));
      expect(results[1].$2, same(second));
      expect(results[0].$1, isNot(same(results[1].$1)));
    });

    // RF-2: a handler that throws must not leak the call's scoped instances.
    test('a call that failed halfway still disposes what it created', () async {
      final log = <String>[];
      final container = await start([
        Scoped<Tracked>(
          (i) => Tracked('tx', log),
          name: 'tx',
          dependsOn: const [],
        ),
        Scoped<Repo>(
          (i) => throw StateError('handler failed'),
          dependsOn: const [],
        ),
      ]);
      final call = container.root.openCall();

      try {
        call<Tracked>('tx');
        call<Repo>();
      } on ProviderCreationError {
        // The request handler failed; the transport closes the call anyway.
      } finally {
        await call.close();
      }

      expect(log, ['dispose tx']);
    });

    test('a value set on the call is resolvable in it only', () async {
      final container = await start([
        Singleton<Clock>((i) => Clock(), dependsOn: const []),
      ]);
      final call = container.root.openCall();
      final other = container.root.openCall();
      final secret = Secret();

      call.set<Secret>(secret);

      expect(call<Secret>(), same(secret));
      expect(call.maybe<Secret>(), same(secret));
      expect(other.maybe<Secret>(), isNull);
    });

    test(
      'a transient binding depending on a scoped one lives in the call',
      () async {
        final container = await start([
          Scoped<Clock>((i) => Clock(), dependsOn: const []),
          Transient<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]),
        ]);
        final call = container.root.openCall();

        expect(call<Repo>().clock, same(call<Clock>()));
      },
    );

    test(
      'a scoped factory sees singletons and call values of its own module',
      () async {
        final container = await start([
          Singleton<Clock>((i) => Clock(), dependsOn: const []),
          Scoped<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]),
        ]);
        final call = container.root.openCall();

        expect(call<Repo>().clock, same(container.root<Clock>()));
      },
    );

    test('a singleton that depends on a scoped binding fails at build', () {
      expect(
        () => ModuleGraph.build(
          AppModule(
            bindings: [
              Scoped<Clock>((i) => Clock(), dependsOn: const []),
              Singleton<Repo>(
                (i) => Repo(i()),
                dependsOn: const [Key<Clock>()],
              ),
            ],
          ),
        ),
        throwsA(isA<CaptiveDependencyError>()),
      );
    });
  });
}
