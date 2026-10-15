import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

void main() {
  group('Problem', () {
    test('uses the RFC 9457 member names and skips absent ones', () {
      const problem = Problem(title: 'Not Found', status: 404);

      expect(problem.toJson(), {
        'type': 'about:blank',
        'title': 'Not Found',
        'status': 404,
      });
    });

    test('lists detail, instance, code, errors and extensions', () {
      const problem = Problem(
        type: 'https://example.com/probs/out-of-credit',
        title: 'Out of credit',
        status: 403,
        detail: 'Balance is 30.',
        instance: '/account/12345',
        code: 'out_of_credit',
        errors: [ProblemError(detail: 'too low', pointer: '/body/amount')],
        extensions: {'balance': 30},
      );

      expect(problem.toJson(), {
        'type': 'https://example.com/probs/out-of-credit',
        'title': 'Out of credit',
        'status': 403,
        'detail': 'Balance is 30.',
        'instance': '/account/12345',
        'code': 'out_of_credit',
        'errors': [
          {'detail': 'too low', 'pointer': '/body/amount'},
        ],
        'balance': 30,
      });
    });

    test('an extension never replaces a standard member', () {
      const problem = Problem(
        title: 'Bad Request',
        status: 400,
        extensions: {'status': 200, 'extra': true},
      );

      expect(problem.toJson()['status'], 400);
      expect(problem.toJson()['extra'], true);
    });
  });

  group('ProblemError', () {
    test('keeps the detail and only the members that are set', () {
      expect(const ProblemError(detail: 'x').toJson(), {'detail': 'x'});
      expect(
        const ProblemError(
          detail: 'x',
          pointer: '/query/a',
          code: 'parameter_invalid',
        ).toJson(),
        {'detail': 'x', 'pointer': '/query/a', 'code': 'parameter_invalid'},
      );
    });
  });
}
