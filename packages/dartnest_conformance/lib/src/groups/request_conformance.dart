import 'dart:convert';

import 'package:test/test.dart';

import '../adapter_under_test.dart';
import '../conformance_server.dart';
import '../raw_http.dart';

/// Requests reach the application as `HttpRequest`s that match what the
/// client sent: method, target, headers, body and connection details.
abstract final class RequestConformance {
  /// Registers the group for [factory].
  static void register(AdapterFactory factory) {
    group('requests', () {
      late ConformanceServer server; // Set in setUp before every test.

      setUp(() async => server = await ConformanceServer.start(factory));
      tearDown(() => server.close());

      test('serves the users app', () async {
        final found = await server.send('GET', '/users/1');
        final created = await server.send(
          'POST',
          '/users',
          headers: {'content-type': 'application/json'},
          body: utf8.encode(jsonEncode({'name': 'cid'})),
        );
        final missing = await server.send('GET', '/users/9');

        // Separate checks: a record compares a Map inside it by identity.
        expect(found.status, 200);
        expect(found.json, {'id': 1, 'name': 'ann'});
        expect(
          (created.status, created.headers.value('location')),
          (201, '/users/3'),
        );
        expect((missing.json as Map)['statusCode'], 404);
      });

      test('passes every method upper-cased', () async {
        for (final method in ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']) {
          final response = await server.send(method, '/probe/echo');

          expect((response.json as Map)['method'], method);
        }
      });

      test('keeps the raw query', () async {
        final response = await server.send('GET', '/probe/echo?b=%20x&a=1&a=2');

        expect((response.json as Map)['query'], 'b=%20x&a=1&a=2');
      });

      test('removes dot segments from the target', () async {
        for (final target in ['/probe/../users/1', '/users/./1']) {
          final response = await RawHttp.exchange(
            server.port,
            RawHttp.head('GET', target),
          );

          expect(response.json, {'id': 1, 'name': 'ann'}, reason: target);
        }
      });

      // Review Focus 3: dart:io parses `//users` as an authority.
      test('reads a target that starts with // as a path', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '//users//1'),
        );

        expect(response.json, {'id': 1, 'name': 'ann'});
      });

      // The client controls X-Forwarded-*: they must not change the route.
      test(
        'routes on the target despite X-Forwarded-Host and -Proto',
        () async {
          final response = await RawHttp.exchange(
            server.port,
            RawHttp.head(
              'GET',
              '/users/1',
              headers: {
                'X-Forwarded-Host': 'x/admin',
                'X-Forwarded-Proto': 'https',
                'Connection': 'close',
              },
            ),
          );

          expect(response.status, 200);
          expect(response.json, {'id': 1, 'name': 'ann'});
        },
      );

      test('keeps %2F inside one path segment', () async {
        final response = await server.send('GET', '/probe/segments/a%2Fb');

        expect(response.json, {'value': 'a/b'});
      });

      test('answers 400 to invalid percent-encoded UTF-8', () async {
        final response = await server.send('GET', '/probe/segments/%FF');

        expect(response.status, 400);
      });

      test('passes multi-valued headers case-insensitively', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head(
            'GET',
            '/probe/echo',
            headers: {
              'X-Multi': 'a',
              'x-multi': 'b',
              'X-CASE': 'Value',
              'Connection': 'close',
            },
          ),
        );
        final headers = (response.json as Map)['headers'] as Map;

        expect(headers['x-multi'], ['a', 'b']);
        expect(headers['x-case'], ['Value']);
      });

      test('sends every set-cookie and repeated header value', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/cookies'),
        );

        expect(response.headers.all('set-cookie'), ['a=1', 'b=2']);
        expect(response.headers.all('x-multi').join(', '), 'one, two');
      });

      test('reports the client address and port', () async {
        final response = await server.send('GET', '/probe/echo');
        final echo = response.json as Map;

        expect(echo['remoteAddress'], '127.0.0.1');
        expect(echo['remotePort'], response.localPort);
      });

      test('reuses a keep-alive connection', () async {
        final ports = [
          for (var i = 0; i < 3; i++)
            (await server.send('GET', '/probe/echo')).localPort,
        ];

        expect(ports.toSet(), hasLength(1));
      });

      test('answers pipelined requests in order', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/echo?n=1', headers: const {}) +
              RawHttp.head('GET', '/probe/echo?n=2'),
        );
        final text = latin1.decode(response.bytes);

        expect('HTTP/1.1 200'.allMatches(text), hasLength(2));
        expect(text.indexOf('n=1'), lessThan(text.indexOf('n=2')));
      });

      test('de-chunks the request body and drops transfer-encoding', () async {
        final head = RawHttp.head(
          'POST',
          '/probe/echo',
          headers: {'Transfer-Encoding': 'chunked', 'Connection': 'close'},
        );
        final response = await RawHttp.exchange(
          server.port,
          '${head}5\r\nhello\r\n0\r\n\r\n',
        );
        final echo = response.json as Map;

        expect(echo['body'], 'hello');
        expect(echo['headers'] as Map, isNot(contains('transfer-encoding')));
      });

      test('adds no default headers of the server library', () async {
        final response = await RawHttp.exchange(
          server.port,
          RawHttp.head('GET', '/probe/empty'),
        );

        expect(response.status, 204);
        expect(response.headers.contains('content-type'), isFalse);
        expect(response.headers.contains('x-frame-options'), isFalse);
        expect(response.headers.contains('x-powered-by'), isFalse);
      });
    });
  }
}
