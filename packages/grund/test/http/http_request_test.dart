import 'dart:convert';

import 'package:grund/grund.dart';
import 'package:test/test.dart';

RequestBody streamed(List<String> chunks) =>
    RequestBody(Stream.fromIterable(chunks.map(utf8.encode)));

void main() {
  group('HttpRequest', () {
    test('upper-cases the method and freezes the headers', () {
      final headers = HeaderMap.of({'X-Id': '1'});
      final request = HttpRequest(
        method: 'get',
        uri: Uri.parse('/users?page=2'),
        headers: headers,
      );
      headers.set('x-id', '2');

      expect(request.method, 'GET');
      expect(request.uri.path, '/users');
      expect(request.uri.queryParameters, {'page': '2'});
      expect(request.headers['x-id'], '1');
      expect(() => request.headers.add('a', 'b'), throwsUnsupportedError);
    });

    test('defaults to an empty body and no connection info', () async {
      final request = HttpRequest(method: 'GET', uri: Uri.parse('/'));

      expect(await request.body.bytes(), isEmpty);
      expect(request.connectionInfo, isNull);
    });
  });

  group('RequestBody', () {
    test('reads a chunked stream once and caches it', () async {
      final body = streamed(['{"a":', '1}']);

      expect(await body.text(), '{"a":1}');
      expect(await body.json(), {'a': 1});
      expect(await body.json(), {'a': 1});
      expect(await body.bytes(), utf8.encode('{"a":1}'));
    });

    test('malformed JSON is a 400, not a crash', () async {
      await expectLater(
        RequestBody.bytes(utf8.encode('{"a":')).json(),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.message,
            'message',
            startsWith('Request body is not valid JSON'),
          ),
        ),
      );
    });

    test('an empty body is a 400 when JSON is expected', () async {
      await expectLater(
        RequestBody.empty().json(),
        throwsA(isA<BadRequestException>()),
      );
    });

    test('malformed UTF-8 is a 400', () async {
      await expectLater(
        RequestBody.bytes(const [0xff, 0xfe]).text(),
        throwsA(isA<BadRequestException>()),
      );
    });

    test('the raw stream can be taken once, then readers fail', () async {
      final body = streamed(['abc']);
      final chunks = await body.stream.toList();

      expect(utf8.decode(chunks.expand((c) => c).toList()), 'abc');
      expect(() => body.stream, throwsStateError);
      expect(() => body.bytes(), throwsStateError);
    });

    test('after a cached read, stream replays the cached bytes', () async {
      final body = streamed(['abc']);
      await body.bytes();

      expect(await body.stream.toList(), [utf8.encode('abc')]);
    });
  });
}
