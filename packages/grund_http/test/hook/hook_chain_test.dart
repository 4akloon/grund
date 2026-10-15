import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

import '../helpers/ctx_factory.dart';
import '../helpers/http_fixtures.dart';
import '../helpers/log_hook.dart';

void main() {
  late CtxFactory contexts;
  late HttpCtx c;
  final log = <String>[];

  setUpAll(() async => contexts = await CtxFactory.start());
  tearDownAll(() => contexts.close());
  setUp(() {
    log.clear();
    c = contexts(requestFor('GET', '/'));
  });

  Future<Object?> handler(HttpCtx _) async {
    log.add('handler');
    return 'result';
  }

  HookChain chain(List<LogHook> hooks) => HookChain(hooks);

  group('HookChain on success', () {
    test('before runs outer to inner, after inner to outer', () async {
      final result = await chain([
        LogHook('global', log),
        LogHook('api', log),
        LogHook('route', log),
      ]).run(c, handler);

      expect(result, 'result');
      expect(log, [
        'before global',
        'before api',
        'before route',
        'handler',
        'after route result',
        'after api result',
        'after global result',
      ]);
    });

    test('an empty chain only runs the handler', () async {
      expect(await const HookChain([]).run(c, handler), 'result');
      expect(log, ['handler']);
    });

    test('a hook awaits its own async before', () async {
      final slow = _SlowHook(log);

      await HookChain([slow, LogHook('after', log)]).run(c, handler);

      expect(log.indexOf('slow done'), lessThan(log.indexOf('before after')));
    });
  });

  group('HookChain failures (RF-1)', () {
    test('a throwing before stops the chain, no after runs at all', () async {
      final failure = StateError('no');

      await expectLater(
        chain([
          LogHook('one', log),
          LogHook('two', log, failBefore: failure),
          LogHook('three', log),
        ]).run(c, handler),
        throwsA(same(failure)),
      );

      expect(log.where((e) => e.startsWith('after')), isEmpty);
      expect(log, isNot(contains('handler')));
      expect(log, isNot(contains('before three')));
    });

    test('onError is offered in reverse order to every hook', () async {
      await expectLater(
        chain([
          LogHook('one', log),
          LogHook('two', log, failBefore: StateError('no')),
          LogHook('three', log),
        ]).run(c, handler),
        throwsStateError,
      );

      expect(log.where((e) => e.startsWith('onError')), [
        'onError three StateError',
        'onError two StateError',
        'onError one StateError',
      ]);
    });

    test(
      'the first non-null onError answers, the rest are not asked',
      () async {
        final response = HttpResponse.text('handled', status: 418);

        final result = await chain([
          LogHook('outer', log, answers: HttpResponse.text('late')),
          LogHook('inner', log, answers: response),
        ]).run(c, (_) => throw const ForbiddenException());

        expect(result, same(response));
        expect(log, [
          'before outer',
          'before inner',
          'onError inner ForbiddenException',
        ]);
      },
    );

    test('a failing handler skips after and reaches onError', () async {
      await expectLater(
        chain([LogHook('one', log)]).run(c, (_) => throw StateError('x')),
        throwsStateError,
      );

      expect(log, ['before one', 'onError one StateError']);
    });

    test(
      'a failing after is offered to onError, with no later after',
      () async {
        final response = HttpResponse.text('recovered');

        final result = await chain([
          LogHook('outer', log, answers: response),
          LogHook('inner', log, failAfter: StateError('late')),
        ]).run(c, handler);

        expect(result, same(response));
        expect(log, contains('onError inner StateError'));
        expect(log, isNot(contains('after outer result')));
      },
    );

    test('an error thrown by onError is what the next hook sees', () async {
      final response = HttpResponse.text('final');

      final result = await chain([
        LogHook('outer', log, answers: response),
        LogHook('inner', log, failOnError: const NotFoundException()),
      ]).run(c, (_) => throw StateError('first'));

      expect(result, same(response));
      expect(log, [
        'before outer',
        'before inner',
        'onError inner StateError',
        'onError outer NotFoundException',
      ]);
    });

    test(
      'without an answer the last error is rethrown with its trace',
      () async {
        final trace = StackTrace.fromString('original trace');

        Object? caught;
        StackTrace? caughtTrace;
        try {
          await chain([
            LogHook('one', log),
          ]).run(c, (_) => Error.throwWithStackTrace(StateError('x'), trace));
        } on StateError catch (error, stackTrace) {
          caught = error;
          caughtTrace = stackTrace;
        }

        expect(caught, isA<StateError>());
        expect(caughtTrace.toString(), 'original trace');
      },
    );
  });
}

final class _SlowHook extends HttpHook {
  _SlowHook(this.log);

  final List<String> log;

  @override
  Future<void> before(HttpCtx c) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    log.add('slow done');
  }
}
