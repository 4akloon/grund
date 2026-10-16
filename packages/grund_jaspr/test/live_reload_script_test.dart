import 'dart:convert';

import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/src/jaspr_error.dart';
import 'package:grund_jaspr/src/live_reload_script.dart';
import 'package:test/test.dart';

void main() {
  final url = Uri.parse('http://127.0.0.1:9000/');

  group('urlFrom', () {
    test('reads the variable grund dev sets', () {
      final read = LiveReloadScript.urlFrom({
        'GRUND_LIVE_RELOAD_URL': 'http://127.0.0.1:9000/',
      }, isProduct: false);

      expect(read, url);
    });

    test('is null without the variable', () {
      expect(LiveReloadScript.urlFrom(const {}, isProduct: false), isNull);
    });

    test('is null in a product build, whatever the variable says', () {
      final read = LiveReloadScript.urlFrom({
        'GRUND_LIVE_RELOAD_URL': 'http://127.0.0.1:9000/',
      }, isProduct: true);

      expect(read, isNull);
    });

    for (final value in ['ftp://127.0.0.1/', '/relative', 'http://', '::']) {
      test('refuses "$value"', () {
        expect(
          () => LiveReloadScript.urlFrom({
            'GRUND_LIVE_RELOAD_URL': value,
          }, isProduct: false),
          throwsA(isA<JasprSetupError>()),
        );
      });
    }
  });

  group('inject', () {
    test('puts the script before the last </body>', () {
      final html = LiveReloadScript.inject(
        '<body>a</body><!-- </body> --></BODY></html>',
        url,
      );

      expect(
        html,
        '<body>a</body><!-- </body> -->${LiveReloadScript.tag(url)}'
        '</BODY></html>',
      );
    });

    test('appends the script to HTML without </body>', () {
      expect(
        LiveReloadScript.inject('<p>a</p>', url),
        '<p>a</p>${LiveReloadScript.tag(url)}',
      );
    });
  });

  test('the tag listens for reload at the URL', () {
    expect(
      LiveReloadScript.tag(url),
      '<script>new EventSource("http://127.0.0.1:9000/")'
      '.addEventListener("reload",function(){location.reload()})</script>',
    );
  });

  test('the URL cannot close the script or the string', () {
    final tag = LiveReloadScript.tag(
      Uri.parse('http://127.0.0.1:9000/a"b</script>\\'),
    );
    final literal = tag.substring(
      '<script>new EventSource('.length,
      tag.indexOf(').addEventListener'),
    );

    expect(tag.indexOf('</script>'), tag.length - '</script>'.length);
    expect(jsonDecode(literal), startsWith('http://127.0.0.1:9000/a'));
  });

  test('a hostile variable value cannot inject markup', () {
    final read = LiveReloadScript.urlFrom({
      'GRUND_LIVE_RELOAD_URL':
          'http://127.0.0.1:9/</script><script>alert(1)</script>',
    }, isProduct: false)!;

    final tag = LiveReloadScript.tag(read);

    expect(tag.indexOf('</script>'), tag.length - '</script>'.length);
    expect(tag, isNot(contains('<script>alert')));
    expect(tag.indexOf('<'), 0);
    expect(tag.split('<').length, 3); // only the opening and closing tag
  });

  group('addTo', () {
    test('leaves a response that is not HTML as it is', () {
      final response = HttpResponse.bytes(
        utf8.encode('<feed></feed>'),
        headers: HeaderMap.of({'content-type': 'application/xml'}),
      );

      expect(
        identical(LiveReloadScript.addTo(response, url), response),
        isTrue,
      );
    });

    test('adds the script to UTF-8 HTML and keeps status and headers', () {
      final response = HttpResponse(
        203,
        headers: HeaderMap.of({
          'content-type': 'text/html; charset=utf-8',
          'x-page': 'yes',
        }),
        body: BytesBody(utf8.encode('<body>ü</body>')),
      );

      final added = LiveReloadScript.addTo(response, url);

      expect(added.status, 203);
      expect(added.headers['x-page'], 'yes');
      expect(
        utf8.decode((added.body as BytesBody).bytes),
        '<body>ü${LiveReloadScript.tag(url)}</body>',
      );
    });
  });
}
