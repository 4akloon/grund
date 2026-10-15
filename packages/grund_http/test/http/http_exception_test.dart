import 'package:grund_http/grund_http.dart';
import 'package:test/test.dart';

class PaymentRequiredException extends HttpException {
  const PaymentRequiredException() : super(402, message: 'Pay first');
}

void main() {
  group('HttpException', () {
    test('message defaults to the reason phrase', () {
      expect(const HttpException(404).message, 'Not Found');
      expect(const HttpException(499).message, 'Unknown Status');
      expect(const HttpException(409, message: 'Taken').message, 'Taken');
    });

    test('built-in subclasses carry their status', () {
      expect(const BadRequestException().status, 400);
      expect(const UnauthorizedException().status, 401);
      expect(const ForbiddenException().status, 403);
      expect(const NotFoundException().status, 404);
      expect(MethodNotAllowedException(const ['GET']).status, 405);
      expect(const PayloadTooLargeException().status, 413);
      expect(const UnprocessableContentException().status, 422);
      expect(const ServiceUnavailableException().status, 503);
    });

    test('code and pointer are kept for the problem body', () {
      const error = BadRequestException(
        code: 'parameter_invalid',
        pointer: '/query/page',
      );
      const unprocessable = UnprocessableContentException(
        code: 'title_taken',
        pointer: '/body/title',
      );

      expect(error.code, 'parameter_invalid');
      expect(error.pointer, '/query/page');
      expect(unprocessable.pointer, '/body/title');
      expect(const NotFoundException().code, isNull);
    });

    test('405 lists the allowed methods in the allow header', () {
      final error = MethodNotAllowedException(const ['GET', 'HEAD', 'POST']);

      expect(error.allowed, ['GET', 'HEAD', 'POST']);
      expect(error.headers, {'allow': 'GET, HEAD, POST'});
    });

    test('applications can extend it and keep details', () {
      const error = PaymentRequiredException();
      const withDetails = BadRequestException(details: {'field': 'name'});

      expect(error.status, 402);
      expect(error.toString(), 'PaymentRequiredException(402): Pay first');
      expect(withDetails.details, {'field': 'name'});
    });
  });

  group('StatusCode', () {
    test('knows reason phrases of common codes', () {
      expect(StatusCode.reasonPhrase(StatusCode.ok), 'OK');
      expect(
        StatusCode.reasonPhrase(StatusCode.methodNotAllowed),
        'Method Not Allowed',
      );
      expect(
        StatusCode.reasonPhrase(StatusCode.payloadTooLarge),
        'Content Too Large',
      );
    });
  });
}
