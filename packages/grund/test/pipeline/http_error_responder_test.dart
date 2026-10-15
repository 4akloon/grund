import 'package:grund/grund.dart';
import 'package:grund/src/pipeline/http_error_responder.dart';
import 'package:test/test.dart';

import '../helpers/http_fixtures.dart';

final class Unprintable {
  @override
  String toString() => 'unprintable';
}

void main() {
  group('HttpErrorResponder', () {
    final logged = <Object>[];
    final responder = HttpErrorResponder(
      debug: false,
      log: (error, stackTrace) => logged.add(error),
    );

    setUp(logged.clear);

    test('HttpException keeps status, message, details and headers', () async {
      final response = responder.respond(
        const UnauthorizedException(
          message: 'Token expired',
          details: {'realm': 'api'},
          headers: {'www-authenticate': 'Bearer'},
        ),
        StackTrace.current,
      );

      expect(response.status, 401);
      expect(response.headers['www-authenticate'], 'Bearer');
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(await jsonOf(response), {
        'statusCode': 401,
        'error': 'Unauthorized',
        'message': 'Token expired',
        'details': {'realm': 'api'},
      });
      expect(logged, isEmpty);
    });

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
        'statusCode': 400,
        'error': 'Bad Request',
        'message': 'Bad input',
      });
    });

    test('an unknown error is a logged 500 without internals', () async {
      final error = StateError('db password is hunter2');

      final response = responder.respond(error, StackTrace.current);

      expect(response.status, 500);
      expect(await jsonOf(response), {
        'statusCode': 500,
        'error': 'Internal Server Error',
        'message': 'Internal server error',
      });
      expect(logged, [same(error)]);
    });

    test('debug mode includes the message and the stack', () async {
      final debug = HttpErrorResponder(debug: true, log: (_, _) {});

      final body =
          await jsonOf(debug.respond(StateError('boom'), StackTrace.current))
              as Map<String, Object?>;

      expect(body['message'], 'Bad state: boom');
      expect(body['stack'], contains('http_error_responder_test.dart'));
    });
  });
}
