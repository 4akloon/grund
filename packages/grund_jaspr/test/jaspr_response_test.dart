import 'dart:convert';
import 'dart:typed_data';

import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/src/jaspr_response.dart';
import 'package:test/test.dart';

HttpResponse _from(Map<String, List<String>> headers, {int status = 200}) =>
    JasprResponse.from((
      statusCode: status,
      body: Uint8List.fromList(utf8.encode('<p>ü</p>')),
      headers: headers,
    ));

void main() {
  test('the status, the body and every set-cookie are kept', () {
    final response = _from({
      'Set-Cookie': ['a=1', 'b=2'],
      'x-page': ['yes'],
    }, status: 203);

    expect(response.status, 203);
    expect(response.headers.all('set-cookie'), ['a=1', 'b=2']);
    expect(response.headers['x-page'], 'yes');
    expect((response.body as BytesBody).bytes, utf8.encode('<p>ü</p>'));
  });

  test('HTML without a charset becomes UTF-8 HTML', () {
    for (final type in [null, 'text/html', 'TEXT/HTML ; level=1']) {
      final response = _from({
        if (type != null) 'Content-Type': [type],
      });

      expect(response.headers['content-type'], 'text/html; charset=utf-8');
    }
  });

  test('a content type of the page wins over Jaspr default', () {
    final response = _from({
      'Content-Type': ['text/html; charset=utf-8'],
      'content-type': ['application/xml'],
    });

    expect(response.headers.all('content-type'), ['application/xml']);
  });

  test('a charset the page chose is kept', () {
    final response = _from({
      'content-type': ['text/html; charset=iso-8859-1'],
    });

    expect(response.headers['content-type'], 'text/html; charset=iso-8859-1');
  });

  test('a page is not cached unless it says so', () {
    final plain = _from({});
    final cached = _from({
      'Cache-Control': ['max-age=60'],
    });

    expect(plain.headers['cache-control'], 'private, no-cache');
    expect(cached.headers['cache-control'], 'max-age=60');
  });

  test('content-length is left to the adapter', () {
    final response = _from({
      'Content-Length': ['999'],
    });

    expect(response.headers.contains('content-length'), isFalse);
  });
}
