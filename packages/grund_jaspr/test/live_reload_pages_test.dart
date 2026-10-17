import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/pages.dart';
import 'helpers/sites.dart';

void main() {
  final url = Uri.parse('http://127.0.0.1:9/</script>');

  test('a page gets the live reload script before </body>', () async {
    final client = await startPublic([
      homePage(const UrlPage()),
    ], config: JasprConfig(liveReloadUrl: url));

    final response = await client.get('/');

    expect(response.text, contains('new EventSource("http://127.0.0.1:9/'));
    expect(response.text, isNot(contains('/</script>"')));
    expect(
      response.text.indexOf('EventSource'),
      lessThan(response.text.lastIndexOf('</body>')),
    );
  });

  test('a page gets no script without a URL', () async {
    final client = await startPublic([homePage(const UrlPage())]);

    final response = await client.get('/');

    expect(response.text, isNot(contains('EventSource')));
  });

  test('a not found page of the site gets the script too', () async {
    final client = await startPublic([
      homePage(const UrlPage()),
    ], config: JasprConfig(liveReloadUrl: url));

    final response = await client.get('/missing');

    expect(response.status, 404);
    expect(response.text, contains('EventSource'));
  });

  test('a page that is not HTML gets no script', () async {
    final client = await startPublic([
      homePage(const UrlPage()),
      Page('/feed.xml', build: (_) => const FeedPage()),
    ], config: JasprConfig(liveReloadUrl: url));

    final response = await client.get('/feed.xml');

    expect(response.text, isNot(contains('EventSource')));
  });
}
