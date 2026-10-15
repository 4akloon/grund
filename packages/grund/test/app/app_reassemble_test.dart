import 'package:grund/grund.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/fake_runner.dart';
import '../helpers/module_fixtures.dart';
import '../helpers/tracked.dart';

/// A module whose declarations come from [ReloadableCode], so a test can
/// change them between reassembles the way a hot reload changes method bodies.
final class ReloadableModule extends StubModule {
  const ReloadableModule(this.code);

  final ReloadableCode code;

  @override
  List<Binding<Object>> get bindings => code.bindings();
}

final class ReloadableCode {
  List<Binding<Object>> Function() bindings = () => const [];
}

void main() {
  late List<String> log;
  late ReloadableCode code;

  setUp(() {
    log = [];
    code = ReloadableCode();
  });

  Future<App> started() async {
    final app = App(root: ReloadableModule(code));
    await app.start();
    addTearDown(app.close);
    return app;
  }

  group('App.reassemble', () {
    test('keeps the singletons whose module and key are unchanged', () async {
      code.bindings = () => [
        Singleton<Tracked>((i) => Tracked('db', log), dependsOn: const []),
      ];
      final app = await started();
      final before = app.container.root<Tracked>();

      await app.reassemble();

      expect(app.container.root<Tracked>(), same(before));
      expect(log, isEmpty);
    });

    test('reassembles the running runners and returns their report', () async {
      final runner = FakeRunner(
        'a',
        log,
        reassembleReport: const ReassembleReport(added: ['GET /b']),
      );
      code.bindings = () => [runnerBinding(runner)];
      final app = await started();

      final report = await app.reassemble();

      expect(report.added, ['GET /b']);
      expect(runner.reassembled, 1);
    });

    test(
      'starts a runner that the new code adds and stops one it removes',
      () async {
        code.bindings = () => [runnerBinding(FakeRunner('old', log))];
        final app = await started();
        log.clear();
        code.bindings = () => [runnerBinding(FakeRunner('fresh', log))];

        await app.reassemble();

        expect(log, ['prepare fresh', 'start fresh', 'stop old']);
      },
    );

    test('a failing new graph leaves the previous state serving', () async {
      final runner = FakeRunner('a', log);
      code.bindings = () => [runnerBinding(runner)];
      final app = await started();
      code.bindings = () => [
        runnerBinding(runner),
        Singleton<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]),
      ];

      await expectLater(app.reassemble(), throwsA(isA<MissingProviderError>()));

      expect(app.isRunning, isTrue);
      expect(runner.reassembled, 0);
      expect(app.container.root<FakeRunner>('a'), same(runner));
    });

    test('a failing runner abandons what the new container created', () async {
      code.bindings = () => [runnerBinding(FakeRunner('a', log))];
      final app = await started();
      log.clear();
      code.bindings = () => [
        runnerBinding(FakeRunner('a', log)),
        Singleton<Tracked>((i) => Tracked('cache', log), dependsOn: const []),
        runnerBinding(FakeRunner('b', log, prepareFailure: StateError('bad'))),
      ];

      await expectLater(app.reassemble(), throwsA(isA<RunnerError>()));

      expect(log, contains('dispose cache'));
      expect(app.isRunning, isTrue);
    });

    test('refuses a second reassemble while one is running', () async {
      code.bindings = () => const [];
      final app = await started();

      final first = app.reassemble();
      await expectLater(
        app.reassemble(),
        throwsA(isA<ApplicationStateError>()),
      );
      await first;
    });

    test('is refused before start and after close', () async {
      final app = App(root: ReloadableModule(code));
      await expectLater(
        app.reassemble(),
        throwsA(isA<ApplicationStateError>()),
      );
      await app.start();
      await app.close();
      await expectLater(
        app.reassemble(),
        throwsA(isA<ApplicationStateError>()),
      );
    });

    test(
      'close waits for a running reassemble and then closes what it produced',
      () async {
        code.bindings = () => [runnerBinding(FakeRunner('a', log))];
        final app = await started();
        log.clear();

        final reassembling = app.reassemble();
        final closing = app.close();
        await Future.wait([reassembling, closing]);

        expect(log.last, 'stop a');
      },
    );

    test(
      'a dropped runner that fails to stop reports it and keeps the new state',
      () async {
        code.bindings = () => [
          runnerBinding(FakeRunner('old', log, stopFailure: StateError('x'))),
        ];
        final app = await started();
        final oldContainer = app.container;
        log.clear();
        code.bindings = () => [
          runnerBinding(FakeRunner('fresh', log)),
          Singleton<Tracked>((i) => Tracked('cache', log), dependsOn: const []),
        ];

        await expectLater(app.reassemble(), throwsA(isA<ShutdownError>()));

        expect(app.isRunning, isTrue);
        expect(app.container, isNot(same(oldContainer)));
        expect(log, isNot(contains('dispose cache')));
        expect(log, contains('start fresh'));
        await app.close();
        expect(log, contains('stop fresh'));
      },
    );
  });
}
