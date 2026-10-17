import 'dart:async';

import 'package:grund/grund.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/fake_runner.dart';
import '../helpers/module_fixtures.dart';
import '../helpers/tracked.dart';

AppModule moduleWith(List<FakeRunner> runners, {List<String>? log}) =>
    AppModule(
      log: log,
      bindings: [for (final runner in runners) runnerBinding(runner)],
    );

void main() {
  group('App.start', () {
    test(
      'prepares every runner and starts the selected ones in order',
      () async {
        final log = <String>[];
        final app = App(
          root: moduleWith([FakeRunner('a', log), FakeRunner('b', log)]),
        );

        await app.start(only: {'b'});

        expect(log, ['prepare a', 'prepare b', 'start b']);
        expect(app.isRunning, isTrue);
        await app.close();
      },
    );

    test('an empty only prepares the runners and starts none', () async {
      final log = <String>[];
      final app = App(root: moduleWith([FakeRunner('a', log)]));

      await app.start(only: const {});

      expect(log, ['prepare a']);
      await app.close();
    });

    // RF-4: a name that matches no runner is reported before anything starts.
    test(
      'an unknown name fails before any runner starts and closes the container',
      () async {
        final log = <String>[];
        final app = App(
          root: AppModule(
            bindings: [
              runnerBinding(FakeRunner('a', log)),
              Singleton<Tracked>(
                (i) => Tracked('db', log),
                dependsOn: const [],
              ),
            ],
          ),
        );

        await expectLater(
          app.start(only: {'nope'}),
          throwsA(isA<UnknownRunnerError>()),
        );

        expect(log, ['dispose db']);
        expect(app.isClosed, isTrue);
      },
    );

    test('a structural error surfaces before any factory runs', () async {
      var created = false;
      final app = App(
        root: AppModule(
          bindings: [
            Singleton<Clock>((i) {
              created = true;
              return Clock();
            }, dependsOn: const []),
            Singleton<Repo>((i) => Repo(i()), dependsOn: const [Key<Config>()]),
          ],
        ),
      );

      await expectLater(app.start(), throwsA(isA<MissingProviderError>()));

      expect(created, isFalse);
      expect(app.isClosed, isTrue);
    });

    // RF-4: a failing start leaves nothing running and nothing open.
    test('a runner that fails to prepare stops the start and releases the container', () async {
      final log = <String>[];
      final app = App(
        root: AppModule(
          bindings: [
            runnerBinding(
              FakeRunner('a', log, prepareFailure: StateError('bad')),
            ),
            Singleton<Tracked>((i) => Tracked('db', log), dependsOn: const []),
          ],
        ),
      );

      await expectLater(app.start(), throwsA(isA<RunnerError>()));

      expect(log, ['prepare a', 'dispose db']);
    });

    // RF-4: a failing start rolls back the runners started before it.
    test(
      'a runner that fails to start rolls back the ones started before it',
      () async {
        final log = <String>[];
        final app = App(
          root: moduleWith([
            FakeRunner('a', log),
            FakeRunner('b', log, startFailure: StateError('bad')),
          ]),
        );

        await expectLater(app.start(), throwsA(isA<RunnerError>()));

        expect(log, ['prepare a', 'prepare b', 'start a', 'start b', 'stop a']);
      },
    );

    test('overrides replace a binding of the graph', () async {
      final app = App(
        root: AppModule(
          bindings: [Singleton<Clock>((i) => Clock(), dependsOn: const [])],
        ),
        overrides: [
          Singleton<Clock>((i) => _FixedClock(), dependsOn: const []),
        ],
      );

      await app.start();

      expect(app.container.root<Clock>(), isA<_FixedClock>());
      await app.close();
    });

    test('cannot start twice or after close', () async {
      final app = App(root: const AppModule());
      await app.start();

      await expectLater(app.start(), throwsA(isA<ApplicationStateError>()));
      await app.close();
      await expectLater(app.start(), throwsA(isA<ApplicationStateError>()));
    });

    test('the container is not available before start', () {
      expect(
        () => App(root: const AppModule()).container,
        throwsA(isA<ApplicationStateError>()),
      );
    });
  });

  group('App.close', () {
    // RF-5: a second (even concurrent) close does nothing.
    test('stops the runners in reverse, then shuts the modules down', () async {
      final log = <String>[];
      final app = App(
        root: moduleWith([
          FakeRunner('a', log),
          FakeRunner('b', log),
        ], log: log),
      );
      await app.start();
      log.clear();

      await app.close();

      expect(log, ['stop b', 'stop a', 'shutdown AppModule']);
    });

    test('is idempotent', () async {
      final log = <String>[];
      final app = App(root: moduleWith([FakeRunner('a', log)]));
      await app.start();

      await Future.wait([app.close(), app.close()]);
      await app.close();

      expect(log.where((e) => e == 'stop a'), hasLength(1));
    });

    // RF-5: failures are collected, not lost.
    test(
      'collects the failures of runners and of the container into one error',
      () async {
        final log = <String>[];
        final app = App(
          root: AppModule(
            bindings: [
              runnerBinding(
                FakeRunner('a', log, stopFailure: StateError('stop')),
              ),
              Singleton<Tracked>(
                (i) => Tracked('db', log, failure: StateError('dispose')),
                dependsOn: const [],
              ),
            ],
          ),
        );
        await app.start();

        await expectLater(
          app.close(),
          throwsA(
            isA<ShutdownError>().having(
              (e) => e.failures,
              'failures',
              hasLength(2),
            ),
          ),
        );
      },
    );

    test('closing an application that never started is allowed', () async {
      final app = App(root: const AppModule());

      await app.close();

      expect(app.isClosed, isTrue);
    });
  });

  group('App.run', () {
    test('serves until a stop signal arrives, then closes', () async {
      final log = <String>[];
      final app = App(root: moduleWith([FakeRunner('a', log)]));
      final stop = StreamController<int>();

      final running = app.run(signals: StopSignals(sources: [stop.stream]));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(log, ['prepare a', 'start a']);

      stop.add(1);
      await running;

      expect(log, ['prepare a', 'start a', 'stop a']);
      expect(app.isClosed, isTrue);
    });
  });
}

final class _FixedClock extends Clock {}
