import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/container.dart';
import 'package:grund/src/di/injector.dart';
import 'package:grund/src/di/module.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/errors/resolution_errors.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/module_fixtures.dart';
import '../helpers/tracked.dart';

Singleton<Tracked> tracked(
  String name,
  List<String> log, {
  Object? failure,
  List<String> after = const [],
}) => Singleton<Tracked>(
  (i) {
    log.add('create $name');
    return Tracked(name, log, failure: failure);
  },
  name: name,
  dependsOn: const [],
);

void main() {
  group('Container lifecycle', () {
    test('runs onInit of every module after all singletons exist', () async {
      final log = <String>[];
      final graph = ModuleGraph.build(
        AppModule(
          log: log,
          imports: [
            DbModule(log: log, bindings: [tracked('db', log)]),
          ],
          bindings: [tracked('app', log)],
        ),
      );

      await Container.create(graph);

      expect(log, [
        'create db',
        'create app',
        'init DbModule',
        'init AppModule',
      ]);
    });

    // RF-5: a second close does nothing.
    test(
      'close runs onShutdown in reverse, then disposes singletons in reverse',
      () async {
        final log = <String>[];
        final container = await Container.create(
          ModuleGraph.build(
            AppModule(
              log: log,
              imports: [
                DbModule(log: log, bindings: [tracked('db', log)]),
              ],
              bindings: [tracked('app', log)],
            ),
          ),
        );
        log.clear();

        await container.close();

        expect(log, [
          'shutdown AppModule',
          'shutdown DbModule',
          'dispose app',
          'dispose db',
        ]);
      },
    );

    // RF-5: every step runs; the failures come back together.
    test('close is idempotent', () async {
      final log = <String>[];
      final container = await Container.create(
        ModuleGraph.build(AppModule(bindings: [tracked('app', log)])),
      );

      await container.close();
      await container.close();

      expect(log.where((e) => e == 'dispose app'), hasLength(1));
    });

    test('close tries every step and reports all failures', () async {
      final log = <String>[];
      final container = await Container.create(
        ModuleGraph.build(
          AppModule(
            bindings: [
              tracked('a', log, failure: StateError('a')),
              tracked('b', log, failure: StateError('b')),
            ],
          ),
        ),
      );

      await expectLater(
        container.close(),
        throwsA(
          isA<ShutdownError>().having(
            (e) => e.failures.map((f) => f.step).toList(),
            'steps',
            [
              'dispose Tracked(\'b\') of AppModule',
              'dispose Tracked(\'a\') of AppModule',
            ],
          ),
        ),
      );
      expect(log.where((e) => e.startsWith('dispose')), hasLength(2));
    });

    test('a failing factory disposes what was already created', () async {
      final log = <String>[];
      final graph = ModuleGraph.build(
        AppModule(
          log: log,
          bindings: [
            tracked('first', log),
            Singleton<Clock>(
              (i) => throw StateError('boom'),
              dependsOn: const [],
            ),
          ],
        ),
      );

      await expectLater(
        Container.create(graph),
        throwsA(isA<ProviderCreationError>()),
      );

      expect(log, ['create first', 'dispose first']);
    });

    test(
      'a failing onInit shuts down the modules that were initialised',
      () async {
        final log = <String>[];
        final graph = ModuleGraph.build(
          AppModule(
            log: log,
            imports: [const _FailingInitModule()],
            bindings: [tracked('app', log)],
          ),
        );

        await expectLater(
          Container.create(graph),
          throwsA(
            isA<ModuleLifecycleError>()
                .having((e) => e.module, 'module', '_FailingInitModule')
                .having((e) => e.phase, 'phase', 'onInit'),
          ),
        );
        expect(log, ['create app', 'dispose app']);
      },
    );

    test('a failing rollback is reported next to the original cause', () async {
      final log = <String>[];
      final graph = ModuleGraph.build(
        AppModule(
          bindings: [
            tracked('first', log, failure: StateError('dispose failed')),
            Singleton<Clock>(
              (i) => throw StateError('boom'),
              dependsOn: const [],
            ),
          ],
        ),
      );

      await expectLater(
        Container.create(graph),
        throwsA(
          isA<StartupRollbackError>()
              .having((e) => e.cause, 'cause', isA<ProviderCreationError>())
              .having((e) => e.failures, 'failures', hasLength(1)),
        ),
      );
    });
  });
}

final class _FailingInitModule extends Module {
  const _FailingInitModule();

  @override
  void onInit(Injector injector) => throw StateError('init failed');
}
