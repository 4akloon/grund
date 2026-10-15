import 'package:grund/src/di/key.dart';
import 'package:grund/src/errors/app_errors.dart';
import 'package:grund/src/errors/graph_errors.dart';
import 'package:grund/src/errors/grund_error.dart';
import 'package:grund/src/errors/resolution_errors.dart';
import 'package:test/test.dart';

class _Repo {}

class _Clock {}

void main() {
  group('GrundError', () {
    test('prints its class name and message', () {
      const error = UnusedOverrideError(Key<_Repo>());

      expect(error, isA<GrundError>());
      expect(error.toString(), startsWith('UnusedOverrideError: '));
      expect(error.toString(), contains(error.message));
    });
  });

  group('graph errors', () {
    test('a circular import prints the cycle path', () {
      const error = CircularModuleImportError(['A', 'B', 'A']);

      expect(error.message, contains('A -> B -> A'));
    });

    test('a duplicate binding names the module and the key', () {
      const error = DuplicateBindingError(
        key: Key<_Repo>(),
        module: 'AppModule',
      );

      expect(error.message, contains('AppModule'));
      expect(error.message, contains('_Repo'));
    });

    test('an invalid export names the module and the export', () {
      const error = InvalidExportError(
        export: Key<_Repo>(),
        module: 'AppModule',
      );

      expect(error.message, contains('AppModule'));
      expect(error.message, contains('_Repo'));
    });

    test('a missing provider names the key, the module and the requirer', () {
      const error = MissingProviderError(
        key: Key<_Repo>(),
        module: 'AppModule',
        requiredBy: Key<_Clock>(),
      );

      expect(error.message, contains('_Repo'));
      expect(error.message, contains('AppModule'));
      expect(error.message, contains('required by _Clock'));
    });

    test(
      'an invisible provider says what to import when it is not reachable',
      () {
        const error = ProviderNotVisibleError(
          key: Key<_Repo>(),
          module: 'AppModule',
          requiredBy: Key<_Clock>(),
          declaredIn: ['DbModule'],
          importChain: [],
        );

        expect(error.message, contains('import DbModule into AppModule'));
      },
    );

    test(
      'an invisible provider prints the import chain when it is indirect',
      () {
        const error = ProviderNotVisibleError(
          key: Key<_Repo>(),
          module: 'AppModule',
          requiredBy: Key<_Clock>(),
          declaredIn: ['DbModule'],
          importChain: ['AppModule', 'TasksModule', 'DbModule'],
        );

        expect(error.message, contains('AppModule -> TasksModule -> DbModule'));
      },
    );

    test('a conflicting module advises different qualifiers', () {
      const error = ConflictingModuleError('DbModule');

      expect(error.message, contains('qualifiers'));
    });

    test('a dependency cycle prints the keys with arrows', () {
      const error = CircularDependencyError([
        Key<_Repo>(),
        Key<_Clock>(),
        Key<_Repo>(),
      ]);

      expect(error.message, contains('_Repo -> _Clock -> _Repo'));
    });

    test('a captive dependency prints the path from the singleton', () {
      const error = CaptiveDependencyError(
        singleton: Key<_Repo>(),
        scoped: Key<_Clock>(),
        path: [Key<_Repo>(), Key<_Clock>()],
      );

      expect(error.message, contains('_Repo -> _Clock'));
      expect(error.message, contains('call-scoped'));
    });

    test('an ambiguous provider lists the owners', () {
      const error = AmbiguousProviderError(
        key: Key<_Repo>(),
        module: 'AppModule',
        owners: ['AuthModule', 'DbModule'],
      );

      expect(error.message, contains('AuthModule and DbModule'));
    });
  });

  group('resolution errors', () {
    test('a failed factory names the key, the chain and the cause', () {
      final error = ProviderCreationError(
        key: const Key<_Repo>(),
        module: 'DbModule',
        chain: const [Key<_Clock>()],
        error: StateError('boom'),
        stackTrace: StackTrace.current,
      );

      expect(error.message, contains('_Repo'));
      expect(error.message, contains('required by _Clock'));
      expect(error.message, contains('boom'));
    });

    test('a scoped key outside a call explains how to open one', () {
      const error = ScopedOutsideCallError(
        key: Key<_Repo>(),
        module: 'AppModule',
      );

      expect(error.message, contains('openCall'));
    });

    test('a shutdown error lists every failed step', () {
      final error = ShutdownError([
        (
          step: 'dispose a',
          error: StateError('a'),
          stackTrace: StackTrace.empty,
        ),
        (
          step: 'onShutdown B',
          error: StateError('b'),
          stackTrace: StackTrace.empty,
        ),
      ]);

      expect(error.message, contains('2 step(s)'));
      expect(error.message, contains('dispose a'));
      expect(error.message, contains('onShutdown B'));
    });

    test('a rollback error keeps the original cause next to the failures', () {
      final error = StartupRollbackError(
        cause: StateError('factory'),
        causeStackTrace: StackTrace.empty,
        failures: [
          (
            step: 'dispose a',
            error: StateError('a'),
            stackTrace: StackTrace.empty,
          ),
        ],
      );

      expect(error.message, contains('factory'));
      expect(error.message, contains('dispose a'));
    });
  });

  group('app errors', () {
    test('a state error reads as a sentence', () {
      const error = ApplicationStateError(
        operation: 'start',
        reason: 'the application is already running',
      );

      expect(
        error.message,
        'Cannot start: the application is already running.',
      );
    });

    test('an unknown runner lists what exists', () {
      const error = UnknownRunnerError(
        unknown: ['nope'],
        available: ['http', 'jobs'],
      );

      expect(error.message, contains('nope'));
      expect(error.message, contains('http, jobs'));
    });

    test('an unknown runner with an empty graph says "none"', () {
      const error = UnknownRunnerError(unknown: ['nope'], available: []);

      expect(error.message, contains('none'));
    });

    test('a runner error names the runner, the phase and the cause', () {
      final error = RunnerError(
        runner: 'http',
        phase: 'start',
        error: StateError('port in use'),
        stackTrace: StackTrace.empty,
      );

      expect(error.message, contains('"http"'));
      expect(error.message, contains('start'));
      expect(error.message, contains('port in use'));
    });

    test('a duplicate runner names the shared name', () {
      const error = DuplicateRunnerError('http');

      expect(error.message, contains('"http"'));
    });
  });
}
