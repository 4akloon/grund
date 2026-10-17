import 'package:grund_http/grund_http.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import '../helpers/http_fixtures.dart';
import '../helpers/log_capture.dart';

final class Unprintable {
  @override
  String toString() => 'unprintable';
}

void main() {
  group('ProblemResponder', () {
    const responder = ProblemResponder(debug: false);
    late LogCapture log; // Set in setUp before every test.

    setUp(() => log = LogCapture.start());

    test('HttpException keeps status, headers and becomes a problem', () async {
      final response = responder.respond(
        const UnauthorizedException(
          message: 'Token expired',
          code: 'token_expired',
          details: {'realm': 'api'},
          headers: {'www-authenticate': 'Bearer'},
        ),
        StackTrace.current,
        instance: '/me',
      );

      expect(response.status, 401);
      expect(response.headers['www-authenticate'], 'Bearer');
      expect(response.headers['content-type'], 'application/problem+json');
      expect(await jsonOf(response), {
        'type': 'about:blank',
        'title': 'Unauthorized',
        'status': 401,
        'detail': 'Token expired',
        'instance': '/me',
        'code': 'token_expired',
        'details': {'realm': 'api'},
      });
      expect(log.unhandledErrors, isEmpty);
    });

    group('an HttpException with a cause', () {
      final trace = StackTrace.fromString('original trace');

      test('503 is logged as SEVERE with the cause and its trace', () async {
        final cause = StateError('db down');

        final response = responder.respond(
          ServiceUnavailableException(cause: cause, causeStackTrace: trace),
          StackTrace.current,
        );
        await log.messages('grund.http');

        final record = log.records.single;
        expect(record.loggerName, 'grund.http');
        expect(record.level, Level.SEVERE);
        expect(record.message, allOf(contains('503'), contains('Service')));
        expect(record.error, same(cause));
        expect(record.stackTrace, same(trace));
        expect(response.status, 503);
      });

      test('404 is logged as FINE', () async {
        final cause = StateError('missing');

        responder.respond(
          NotFoundException(
            code: 'task_not_found',
            cause: cause,
            causeStackTrace: trace,
          ),
          StackTrace.current,
        );
        await log.messages('grund.http');

        final record = log.records.single;
        expect(record.level, Level.FINE);
        expect(
          record.message,
          allOf(contains('404'), contains('task_not_found')),
        );
        expect(record.error, same(cause));
        expect(record.stackTrace, same(trace));
      });

      test('the body never reveals the cause', () async {
        final response = const ProblemResponder(debug: true).respond(
          ServiceUnavailableException(
            cause: StateError('secret'),
            causeStackTrace: trace,
          ),
          StackTrace.current,
        );

        expect(await jsonOf(response), {
          'type': 'about:blank',
          'title': 'Service Unavailable',
          'status': 503,
          'detail': 'Service Unavailable',
        });
      });
    });

    test('an HttpException without a cause is not logged', () async {
      responder.respond(
        const ServiceUnavailableException(),
        StackTrace.current,
      );
      await log.messages('grund.http');

      expect(log.records, isEmpty);
    });

    test('a pointer becomes an entry of errors', () async {
      final response = responder.respond(
        const BadRequestException(
          message: 'Invalid query parameter "page".',
          code: 'parameter_invalid',
          pointer: '/query/page',
        ),
        StackTrace.current,
      );

      expect((await jsonOf(response) as Map)['errors'], [
        {
          'detail': 'Invalid query parameter "page".',
          'pointer': '/query/page',
          'code': 'parameter_invalid',
        },
      ]);
    });

    test('details that are problem errors become errors', () async {
      final response = responder.respond(
        const UnprocessableContentException(
          details: [
            ProblemError(detail: 'required', pointer: '/body/title'),
            ProblemError(detail: 'too long', pointer: '/body/note'),
          ],
        ),
        StackTrace.current,
      );

      final body = await jsonOf(response) as Map<String, Object?>;
      expect(response.status, 422);
      expect(body['errors'], hasLength(2));
      expect(body, isNot(contains('details')));
    });

    test('problem errors in a List<Object> become errors too', () async {
      final response = responder.respond(
        UnprocessableContentException(
          details: <Object>[
            const ProblemError(detail: 'required', pointer: '/body/title'),
          ],
        ),
        StackTrace.current,
      );

      final body = await jsonOf(response) as Map<String, Object?>;
      expect(body['errors'], hasLength(1));
      expect(body, isNot(contains('details')));
    });

    test(
      'an empty list of problem errors yields no errors and no details',
      () async {
        final response = responder.respond(
          const BadRequestException(details: <ProblemError>[]),
          StackTrace.current,
        );

        final body = await jsonOf(response) as Map<String, Object?>;
        expect(body, isNot(contains('details')));
      },
    );

    test('details without a JSON form are sent as text', () async {
      final response = responder.respond(
        BadRequestException(details: Unprintable()),
        StackTrace.current,
      );

      expect((await jsonOf(response) as Map)['details'], 'unprintable');
    });

    test('cyclic details are dropped, the rest of the body is kept', () async {
      final cyclic = <Object?, Object?>{};
      cyclic['self'] = cyclic;

      final response = responder.respond(
        BadRequestException(message: 'Bad input', details: cyclic),
        StackTrace.current,
      );

      expect(response.status, 400);
      expect(await jsonOf(response), {
        'type': 'about:blank',
        'title': 'Bad Request',
        'status': 400,
        'detail': 'Bad input',
      });
    });

    test('an unknown error is a logged 500 without internals', () async {
      final error = StateError('db password is hunter2');

      final response = responder.respond(error, StackTrace.current);

      expect(response.status, 500);
      expect(response.headers['content-type'], 'application/problem+json');
      expect(await jsonOf(response), {
        'type': 'about:blank',
        'title': 'Internal Server Error',
        'status': 500,
        'detail': 'Internal server error',
      });
      expect(log.unhandledErrors, [same(error)]);
      expect(log.records.single.stackTrace, isNotNull);
    });

    test('debug mode includes the error and the stack', () async {
      final debug = ProblemResponder(debug: true);

      final body = await jsonOf(
        debug.respond(StateError('boom'), StackTrace.current),
      ) as Map<String, Object?>;

      expect(body['detail'], 'Bad state: boom');
      expect(body['stack'], contains('problem_responder_test.dart'));
    });
  });
}
