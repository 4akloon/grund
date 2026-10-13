import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

class Point {
  Point(this.x);
  final int x;
  Map<String, Object?> toJson() => {'x': x};
}

Future<String> bodyText(HttpResponse response) async =>
    utf8.decode(await response.body.readAll());

void main() {
  group('HttpResponse factories', () {
    test('text sets the content type and encodes UTF-8', () async {
      final response = HttpResponse.text('привіт', status: 201);

      expect(response.status, 201);
      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
      expect(await bodyText(response), 'привіт');
    });

    test('json encodes maps and toJson objects', () async {
      final response = HttpResponse.json({'p': Point(1)});

      expect(response.status, 200);
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(await bodyText(response), '{"p":{"x":1}}');
    });

    test('explicit content-type is kept', () {
      final response = HttpResponse.text(
        '<b>hi</b>',
        headers: HeaderMap.of({'Content-Type': 'text/html'}),
      );

      expect(response.headers['content-type'], 'text/html');
    });

    test('bytes, stream, redirect and empty', () async {
      expect(
        HttpResponse.bytes(const [1, 2]).headers['content-type'],
        'application/octet-stream',
      );
      final streamed = HttpResponse.stream(
        Stream.fromIterable([
          [1],
          [2, 3],
        ]),
        contentType: 'text/csv',
      );
      expect(await streamed.body.readAll(), [1, 2, 3]);
      expect(streamed.headers['content-type'], 'text/csv');

      final redirect = HttpResponse.redirect(Uri.parse('/login'));
      expect(redirect.status, 302);
      expect(redirect.headers['location'], '/login');
      expect(HttpResponse.empty().status, 204);
    });

    test('status outside 100-599 is rejected', () {
      expect(() => HttpResponse(42), throwsRangeError);
      expect(() => HttpResponse(600), throwsRangeError);
    });

    test('headers are read-only', () {
      expect(
        () => HttpResponse.text('x').headers.add('a', 'b'),
        throwsUnsupportedError,
      );
    });
  });

  group('HttpResponse.mergeHeaders', () {
    test('adds missing names and keeps the response values', () {
      final response = HttpResponse.text('x').mergeHeaders(
        HeaderMap.of({'content-type': 'text/html', 'x-trace': '7'}),
      );

      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
      expect(response.headers['x-trace'], '7');
    });

    test('returns the same response when nothing is missing', () {
      final response = HttpResponse.text('x');

      expect(response.mergeHeaders(HeaderMap()), same(response));
    });
  });

  group('ResponseHead', () {
    test('starts without a status and with writable headers', () {
      final head = ResponseHead()..headers.set('x-a', '1');

      expect(head.status, isNull);
      expect(head.headers['x-a'], '1');
    });
  });
}
