import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/pipeline/pipeline.dart';
import 'package:dartnest/src/pipeline/resolved_enhancers.dart';
import 'package:test/test.dart';

import '../helpers/pipeline_fixtures.dart';

Object? identity(Object? result) => result;

void main() {
  group('Pipeline.run', () {
    test('guards, interceptors, handler, finish in order', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        enhancers: ResolvedEnhancers(
          guards: [LogGuard(log, 'app'), LogGuard(log, 'route')],
          interceptors: [
            LogInterceptor(log, 'outer'),
            LogInterceptor(log, 'inner'),
          ],
        ),
      );

      final result = await Pipeline.run(endpoint, plainContext(), (r) {
        log.add('finish');
        return r;
      });

      expect(result, 'result');
      expect(log, [
        'guard app',
        'guard route',
        'before outer',
        'before inner',
        'handler',
        'after inner',
        'after outer',
        'finish',
      ]);
    });

    test('a false guard stops the chain with 403', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        enhancers: ResolvedEnhancers(
          guards: [LogGuard(log, 'a', allow: false), LogGuard(log, 'b')],
        ),
      );

      await expectLater(
        Pipeline.run(endpoint, plainContext(), identity),
        throwsA(isA<ForbiddenException>()),
      );
      expect(log, ['guard a']);
    });

    test('an interceptor can answer without the handler', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        enhancers: ResolvedEnhancers(interceptors: [_ShortCircuit()]),
      );

      expect(await Pipeline.run(endpoint, plainContext(), identity), 'cached');
      expect(log, isEmpty);
    });

    test('an interceptor can replace the result', () async {
      final endpoint = endpointWith(
        [],
        enhancers: ResolvedEnhancers(interceptors: [_Wrap()]),
      );

      expect(await Pipeline.run(endpoint, plainContext(), identity), {
        'data': 'result',
      });
    });
  });

  group('Pipeline.run exception filters', () {
    test('first matching filter handles, result goes through finish', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        handler: () => throw StateError('boom'),
        enhancers: ResolvedEnhancers(
          filters: [
            LogFilter<ArgumentError>(log, 'args'),
            LogFilter<StateError>(log, 'state'),
            LogFilter<Object>(log, 'any'),
          ],
        ),
      );

      final result = await Pipeline.run(
        endpoint,
        plainContext(),
        (r) => 'finished: $r',
      );

      expect(result, 'finished: state handled Bad state: boom');
      expect(log, ['handler', 'filter state']);
    });

    test('a throwing filter passes the new error to later filters', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        handler: () => throw StateError('db down'),
        enhancers: ResolvedEnhancers(
          filters: [
            LogFilter<StateError>(
              log,
              'map',
              rethrowAs: const NotFoundException(),
            ),
            LogFilter<StateError>(log, 'unreached'),
            LogFilter<HttpException>(log, 'http'),
          ],
        ),
      );

      final result = await Pipeline.run(endpoint, plainContext(), identity);

      expect(result, startsWith('http handled NotFoundException(404)'));
      expect(log, ['handler', 'filter map', 'filter http']);
    });

    test('a throwing catches passes the new error to later filters', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        handler: () => throw StateError('db down'),
        enhancers: ResolvedEnhancers(
          filters: [
            _ThrowingCatches(NotFoundException()),
            LogFilter<StateError>(log, 'skipped'),
            LogFilter<HttpException>(log, 'http'),
          ],
        ),
      );

      final result = await Pipeline.run(endpoint, plainContext(), identity);

      expect(result, startsWith('http handled NotFoundException(404)'));
      expect(log, ['handler', 'filter http']);
    });

    test('guard and finish errors reach the filters too', () async {
      final log = <String>[];
      final endpoint = endpointWith(
        log,
        enhancers: ResolvedEnhancers(
          guards: [LogGuard(log, 'deny', allow: false)],
          filters: [LogFilter<ForbiddenException>(log, 'forbidden')],
        ),
      );

      expect(
        await Pipeline.run(endpoint, plainContext(), identity),
        startsWith('forbidden handled'),
      );

      final failingFinish = endpointWith(
        log,
        enhancers: ResolvedEnhancers(
          filters: [LogFilter<FormatException>(log, 'fmt')],
        ),
      );
      expect(
        await Pipeline.run(failingFinish, plainContext(), (r) {
          if (r == 'result') throw const FormatException('bad');
          return r;
        }),
        startsWith('fmt handled'),
      );
    });

    test('an unhandled error is rethrown with its stack trace', () async {
      final endpoint = endpointWith([], handler: _throwDeep);

      await expectLater(
        Pipeline.run(endpoint, plainContext(), identity),
        throwsA(isA<FormatException>()),
      );
      try {
        await Pipeline.run(endpoint, plainContext(), identity);
      } on FormatException catch (_, stackTrace) {
        expect(stackTrace.toString(), contains('_throwDeep'));
      }
    });
  });
}

Never _throwDeep() => throw const FormatException('deep');

final class _ShortCircuit implements Interceptor {
  @override
  Object? intercept(ExecutionContext context, Next<Object?> next) => 'cached';
}

final class _Wrap implements Interceptor {
  @override
  Future<Object?> intercept(
    ExecutionContext context,
    Next<Object?> next,
  ) async => {'data': await next()};
}

final class _ThrowingCatches extends ExceptionFilter<StateError> {
  _ThrowingCatches(this.failure);
  final Object failure;

  @override
  bool catches(Object error) => throw failure;

  @override
  Object? handle(StateError error, ExecutionContext context) => 'unreached';
}
