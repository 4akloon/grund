import 'dart:io' as io;

import 'package:grund_shelf/src/shelf_request_mapper.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

/// Connection details as `shelf_io` stores them in the request context.
final class FakeConnectionInfo implements io.HttpConnectionInfo {
  @override
  final io.InternetAddress remoteAddress = io.InternetAddress.loopbackIPv4;

  @override
  final int remotePort = 50123;

  @override
  final int localPort = 8080;
}

void main() {
  group('ShelfRequestMapper', () {
    test('keeps the method, the path and the raw query', () {
      final request = ShelfRequestMapper.map(
        shelf.Request('get', Uri.parse('http://localhost/users/1?b=%20x&a=1')),
      );

      expect(request.method, 'GET');
      expect(request.uri.path, '/users/1');
      expect(request.uri.query, 'b=%20x&a=1');
    });

    test('uses the path relative to the handler path', () {
      final request = ShelfRequestMapper.map(
        shelf.Request(
          'GET',
          Uri.parse('http://localhost/api/users/1'),
          handlerPath: '/api/',
        ),
      );

      expect(request.uri.path, '/users/1');
    });

    test('keeps %2F inside one segment', () {
      final request = ShelfRequestMapper.map(
        shelf.Request('GET', Uri.parse('http://localhost/files/a%2Fb')),
      );

      expect(request.uri.pathSegments, ['files', 'a/b']);
    });

    test('copies every header value case-insensitively', () {
      final request = ShelfRequestMapper.map(
        shelf.Request(
          'GET',
          Uri.parse('http://localhost/'),
          headers: {
            'X-Multi': ['a', 'b'],
            'X-Case': 'Value',
          },
        ),
      );

      expect(request.headers.all('x-multi'), ['a', 'b']);
      expect(request.headers['X-CASE'], 'Value');
    });

    test('passes the body unread', () async {
      final request = ShelfRequestMapper.map(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost/'),
          body: Stream.fromIterable([
            [1, 2],
            [3],
          ]),
        ),
      );

      expect(await request.body.bytes(), [1, 2, 3]);
    });

    test('reads the client address from the shelf_io context', () {
      final served = ShelfRequestMapper.map(
        shelf.Request(
          'GET',
          Uri.parse('http://localhost/'),
          context: {ShelfRequestMapper.connectionInfoKey: FakeConnectionInfo()},
        ),
      );
      final embedded = ShelfRequestMapper.map(
        shelf.Request('GET', Uri.parse('http://localhost/')),
      );

      expect(served.connectionInfo?.remoteAddress, '127.0.0.1');
      expect(served.connectionInfo?.remotePort, 50123);
      expect(embedded.connectionInfo, isNull);
    });
  });
}
