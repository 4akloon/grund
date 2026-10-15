import 'dart:async';

import 'package:grund/grund.dart';
import 'package:grund/src/app/app_log.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import '../helpers/fake_runner.dart';
import '../helpers/log_capture.dart';
import '../helpers/module_fixtures.dart';

final class _FailingInitModule extends StubModule {
  const _FailingInitModule();

  @override
  FutureOr<void> onInit(Injector injector) => throw StateError('no init');
}

final class _ReloadModule extends StubModule {
  const _ReloadModule(this.runner);

  final FakeRunner runner;

  @override
  List<Binding<Object>> get bindings => [runnerBinding(runner)];
}

final class _FlakyModule extends StubModule {
  _FlakyModule();

  bool failing = false;

  @override
  List<Binding<Object>> get bindings =>
      failing ? throw StateError('bindings broke') : const [];
}

Matcher initialized(String module) =>
    matches('^$module initialized \\+\\d+ms\$');

void main() {
  late LogCapture capture;

  setUp(() => capture = LogCapture.start());

  group('App lifecycle logging', () {
    test('start logs the application steps', () async {
      final app = App(
        root: AppModule(bindings: [runnerBinding(FakeRunner('a', []))]),
      );
      await app.start();
      addTearDown(app.close);

      expect(await capture.messages(AppLog.loggerName), [
        AppLog.startingMessage,
        '1 singletons created',
        matches(r'^Application started \+\d+ms$'),
      ]);
    });

    test('start logs each module after its init, dependencies first', () async {
      final app = App(
        root: const AppModule(imports: [DbModule(), AuthModule()]),
      );
      await app.start();
      addTearDown(app.close);

      expect(await capture.messages('grund.modules'), [
        initialized('DbModule'),
        initialized('AuthModule'),
        initialized('AppModule'),
      ]);
    });

    test('close logs the shutdown', () async {
      final app = App(root: const AppModule());
      await app.start();
      await app.close();

      final messages = await capture.messages(AppLog.loggerName);
      expect(messages.skip(messages.length - 2), [
        AppLog.shuttingDownMessage,
        AppLog.closedMessage,
      ]);
    });

    test('a failing runner logs the rollback as a warning', () async {
      final app = App(
        root: AppModule(
          bindings: [
            runnerBinding(
              FakeRunner('a', [], startFailure: StateError('port')),
            ),
          ],
        ),
      );

      await expectLater(app.start, throwsA(isA<RunnerError>()));

      final warnings = capture.records.where((r) => r.level == Level.WARNING);
      expect(warnings.single.message, startsWith(AppLog.rollbackMessage));
      expect(warnings.single.message, contains('port'));
    });

    test('a failing module init logs the rollback as a warning', () async {
      final app = App(root: const _FailingInitModule());

      await expectLater(app.start, throwsA(isA<ModuleLifecycleError>()));

      await capture.messages(AppLog.loggerName);
      expect(
        capture.records.where((r) => r.level == Level.WARNING),
        hasLength(1),
      );
    });

    test('reassemble logs how many entries changed', () async {
      final runner = FakeRunner(
        'a',
        [],
        reassembleReport: const ReassembleReport(
          added: ['GET /a', 'GET /b'],
          removed: ['GET /c'],
        ),
      );
      final app = App(root: _ReloadModule(runner));
      await app.start();
      addTearDown(app.close);

      await app.reassemble();

      expect(
        await capture.messages(AppLog.loggerName),
        contains('Reassembled: +2 added, -1 removed'),
      );
    });

    test('a failing reassemble logs a warning and rethrows', () async {
      final flaky = _FlakyModule();
      final app = App(root: flaky);
      await app.start();
      addTearDown(app.close);
      flaky.failing = true;

      await expectLater(app.reassemble, throwsStateError);

      final warnings = capture.records.where((r) => r.level == Level.WARNING);
      expect(
        warnings.single.message,
        startsWith(AppLog.reassembleFailedMessage),
      );
    });
  });

  group('App.run logging', () {
    test('attaches the output while it runs and detaches it after', () async {
      final lines = <String>[];
      final stop = StreamController<Object?>();
      final running = App(root: const AppModule()).run(
        signals: StopSignals(sources: [stop.stream]),
        log: LogOutput.console(sink: lines.add),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      stop.add(null);
      await running;
      await Future<void>.delayed(Duration.zero);

      expect(lines.first, endsWith(AppLog.startingMessage));
      expect(lines.last, endsWith(AppLog.closedMessage));
      final count = lines.length;
      Logger('grund.app').info('after');
      await Future<void>.delayed(Duration.zero);
      expect(lines, hasLength(count));
    });
  });
}
