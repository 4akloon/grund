import 'package:grund/grund.dart';
import 'package:grund/src/app/runner_set.dart';
import 'package:test/test.dart';

import '../helpers/fake_runner.dart';
import '../helpers/module_fixtures.dart';

Future<Injector> injector() async {
  final app = App(root: const AppModule());
  await app.start(only: const {});
  addTearDown(app.close);
  return app.container.root;
}

void main() {
  group('RunnerSet.select', () {
    test('selects everything without only', () async {
      final log = <String>[];
      final set = RunnerSet.select([
        FakeRunner('a', log),
        FakeRunner('b', log),
      ]);

      await set.start(await injector());

      expect(log, ['start a', 'start b']);
    });

    // RF-4: an unknown name is rejected with the names that exist.
    test('selects only the named runners but prepares them all', () async {
      final log = <String>[];
      final set = RunnerSet.select(
        [FakeRunner('a', log), FakeRunner('b', log)],
        only: {'b'},
      );
      final i = await injector();

      await set.prepare(i);
      await set.start(i);

      expect(log, ['prepare a', 'prepare b', 'start b']);
    });

    test('rejects an unknown name and lists what exists', () {
      expect(
        () =>
            RunnerSet.select([FakeRunner('http', [])], only: {'jobs', 'cron'}),
        throwsA(
          isA<UnknownRunnerError>()
              .having((e) => e.unknown, 'unknown', ['cron', 'jobs'])
              .having((e) => e.available, 'available', ['http']),
        ),
      );
    });

    test('rejects two runners with one name', () {
      expect(
        () => RunnerSet.select([FakeRunner('a', []), FakeRunner('a', [])]),
        throwsA(isA<DuplicateRunnerError>().having((e) => e.name, 'name', 'a')),
      );
    });
  });

  group('RunnerSet lifecycle', () {
    test('wraps a failure of a runner with its name and phase', () async {
      final set = RunnerSet.select([
        FakeRunner('a', [], prepareFailure: StateError('bad')),
      ]);

      await expectLater(
        set.prepare(await injector()),
        throwsA(
          isA<RunnerError>()
              .having((e) => e.runner, 'runner', 'a')
              .having((e) => e.phase, 'phase', 'prepare')
              .having((e) => e.error, 'error', isA<StateError>()),
        ),
      );
    });

    // RF-4: runners started before the failing one are stopped again.
    test('lets a GrundError of a runner through unwrapped', () async {
      final set = RunnerSet.select([
        FakeRunner(
          'a',
          [],
          prepareFailure: const ApplicationStateError(
            operation: 'x',
            reason: 'y',
          ),
        ),
      ]);

      await expectLater(
        set.prepare(await injector()),
        throwsA(isA<ApplicationStateError>()),
      );
    });

    test('a failing start stops the runners already started', () async {
      final log = <String>[];
      final set = RunnerSet.select([
        FakeRunner('a', log),
        FakeRunner('b', log, startFailure: StateError('bad')),
        FakeRunner('c', log),
      ]);

      await expectLater(
        set.start(await injector()),
        throwsA(isA<RunnerError>().having((e) => e.runner, 'runner', 'b')),
      );

      expect(log, ['start a', 'start b', 'stop a']);
    });

    test('stop goes in reverse and tries every runner', () async {
      final log = <String>[];
      final set = RunnerSet.select([
        FakeRunner('a', log, stopFailure: StateError('a')),
        FakeRunner('b', log, stopFailure: StateError('b')),
      ]);
      await set.start(await injector());
      log.clear();

      final failures = await set.stop();

      expect(log, ['stop b', 'stop a']);
      expect(failures.map((f) => f.step), ['stop runner b', 'stop runner a']);
    });

    test('a failed rollback is reported next to the failed start', () async {
      final set = RunnerSet.select([
        FakeRunner('a', [], stopFailure: StateError('stuck')),
        FakeRunner('b', [], startFailure: StateError('bad')),
      ]);

      await expectLater(
        set.start(await injector()),
        throwsA(
          isA<StartupRollbackError>().having(
            (e) => e.failures,
            'failures',
            hasLength(1),
          ),
        ),
      );
    });
  });

  group('RunnerSet.reassembleInto', () {
    test(
      'reassembles a runner both sets share and merges the reports',
      () async {
        final log = <String>[];
        final shared = FakeRunner(
          'a',
          log,
          reassembleReport: const ReassembleReport(added: ['x']),
        );
        final previous = RunnerSet.select([shared]);
        final i = await injector();
        await previous.start(i);
        final next = RunnerSet.select([shared]);

        final report = (await previous.reassembleInto(next, i)).report;

        expect(report.added, ['x']);
        expect(shared.reassembled, 1);
        expect(log, ['start a', 'reassemble a']);
      },
    );

    test(
      'prepares and starts a runner that is new, stops one that is gone',
      () async {
        final log = <String>[];
        final old = FakeRunner('old', log);
        final fresh = FakeRunner('fresh', log);
        final previous = RunnerSet.select([old]);
        final i = await injector();
        await previous.start(i);
        log.clear();

        await previous.reassembleInto(RunnerSet.select([fresh]), i);

        expect(log, ['prepare fresh', 'start fresh', 'stop old']);
      },
    );

    test(
      'a failure stops what the new set started and leaves the old running',
      () async {
        final log = <String>[];
        final kept = FakeRunner('kept', log);
        final previous = RunnerSet.select([kept]);
        final i = await injector();
        await previous.start(i);
        log.clear();
        final next = RunnerSet.select([
          FakeRunner('fresh', log),
          FakeRunner('broken', log, prepareFailure: StateError('bad')),
          kept,
        ]);

        await expectLater(
          previous.reassembleInto(next, i),
          throwsA(isA<RunnerError>()),
        );

        expect(log, [
          'prepare fresh',
          'start fresh',
          'prepare broken',
          'stop fresh',
        ]);
        expect(await previous.stop(), isEmpty);
        expect(log.last, 'stop kept');
      },
    );
  });
}
