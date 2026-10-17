import 'dart:convert';

import 'package:grund_http/grund_http.dart';
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

    test('adds every set-cookie of extra before the response\'s own', () {
      final own = HttpResponse(
        303,
        headers: HeaderMap()..add('set-cookie', 'flash=1'),
      );
      final extra = HeaderMap()
        ..add('set-cookie', 'sid=a')
        ..add('set-cookie', 'theme=b');

      final response = own.mergeHeaders(extra);

      expect(response.headers.all('set-cookie'), [
        'sid=a',
        'theme=b',
        'flash=1',
      ]);
    });

    test('carries extra cookies as separate headers when it has none', () {
      final extra = HeaderMap()
        ..add('set-cookie', 'sid=a; Path=/')
        ..add('set-cookie', 'theme=b; Path=/');

      final response = HttpResponse.text('x').mergeHeaders(extra);

      expect(response.headers.all('set-cookie'), [
        'sid=a; Path=/',
        'theme=b; Path=/',
      ]);
    });

    test('returns the same response when nothing is missing', () {
      final response = HttpResponse.text('x');

      expect(response.mergeHeaders(HeaderMap()), same(response));
    });
  });

  group('HttpResponse.withVary', () {
    test('adds the header name', () {
      final response = HttpResponse.text('x').withVary('accept');

      expect(response.headers.all('vary'), ['accept']);
    });

    test('does not duplicate a name, case-insensitively', () {
      final once = HttpResponse.text('x').withVary('accept');

      expect(once.withVary('Accept').headers.all('vary'), ['accept']);
    });

    test('leaves vary: * alone', () {
      final response = HttpResponse.text(
        'x',
        headers: HeaderMap.of({'vary': '*'}),
      );

      expect(response.withVary('accept'), same(response));
    });

    test('keeps one line with the existing tokens first', () {
      final response = HttpResponse.text(
        'x',
        headers: HeaderMap.of({'vary': 'cookie'}),
      ).withVary('accept');

      expect(response.headers.all('vary'), ['cookie, accept']);
      expect(response.headers['vary'], contains('accept'));
    });

    test('keeps body, status and other headers', () async {
      final response = HttpResponse.text('x', status: 201).withVary('accept');

      expect(response.status, 201);
      expect(response.headers['content-type'], 'text/plain; charset=utf-8');
      expect(await bodyText(response), 'x');
    });
  });

  group('HttpResponse.mergeHeaders vary and link', () {
    test('vary lists own tokens, then new ones', () {
      final extra = HeaderMap()..add('vary', 'cookie, Accept');
      final own = HttpResponse.text(
        'x',
        headers: HeaderMap.of({'vary': 'accept, origin'}),
      );

      final response = own.mergeHeaders(extra);

      expect(response.headers.all('vary'), ['accept, origin, cookie']);
    });

    test('vary is taken from extra when the response has none', () {
      final extra = HeaderMap()..add('vary', 'cookie');

      final response = HttpResponse.text('x').mergeHeaders(extra);

      expect(response.headers.all('vary'), ['cookie']);
    });

    test('vary: * on either side absorbs everything', () {
      final star = HeaderMap()..add('vary', '*');
      final own = HttpResponse.text(
        'x',
        headers: HeaderMap.of({'vary': 'accept'}),
      );

      expect(own.mergeHeaders(star).headers.all('vary'), ['*']);
      expect(
        HttpResponse.text(
          'x',
          headers: star,
        ).mergeHeaders(HeaderMap.of({'vary': 'cookie'})).headers.all('vary'),
        ['*'],
      );
    });

    test('link keeps both, extra first', () {
      final extra = HeaderMap()..add('link', '</a>; rel="alternate"');
      final own = HttpResponse.text(
        'x',
        headers: HeaderMap.of({'link': '</b>; rel="canonical"'}),
      );

      final response = own.mergeHeaders(extra);

      expect(response.headers.all('link'), [
        '</a>; rel="alternate"',
        '</b>; rel="canonical"',
      ]);
    });

    test('another name keeps the own values', () {
      final extra = HeaderMap()..add('x-a', 'extra');
      final own = HttpResponse.text('x', headers: HeaderMap.of({'x-a': 'own'}));

      expect(own.mergeHeaders(extra).headers.all('x-a'), ['own']);
    });
  });

  group('StatusCode redirects', () {
    test('permanent redirect codes and phrases', () {
      expect(StatusCode.movedPermanently, 301);
      expect(StatusCode.permanentRedirect, 308);
      expect(StatusCode.reasonPhrase(308), 'Permanent Redirect');
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
