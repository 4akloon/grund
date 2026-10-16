import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/pages.dart';
import 'helpers/pages_app.dart';
import 'helpers/temp_dir.dart';

void main() {
  final url = Uri.parse('http://127.0.0.1:9/</script>');

  test('a page gets the live reload script before </body>', () async {
    final client = await PagesApp.start([
      JasprModule(
        app: UrlPage.new,
        config: JasprConfig(liveReloadUrl: url),
      ),
    ]);

    final response = await client.get('/');

    expect(response.text, contains('new EventSource("http://127.0.0.1:9/'));
    expect(response.text, isNot(contains('/</script>"')));
    expect(
      response.text.indexOf('EventSource'),
      lessThan(response.text.lastIndexOf('</body>')),
    );
  });

  test('a page gets no script without a URL', () async {
    final client = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final response = await client.get('/');

    expect(response.text, isNot(contains('EventSource')));
  });

  test('a page that is not HTML gets no script', () async {
    final client = await PagesApp.start([
      JasprModule(
        app: FeedPage.new,
        config: JasprConfig(liveReloadUrl: url),
      ),
    ]);

    final response = await client.get('/feed.xml');

    expect(response.text, isNot(contains('EventSource')));
  });

  test('a static HTML file is served as it is', () async {
    final dir = TempDir.create();
    dir.write('web/about.html', '<html><body>about</body></html>');
    final client = await PagesApp.start([
      JasprModule(
        app: UrlPage.new,
        config: JasprConfig(
          staticDirectory: dir.resolve('web'),
          liveReloadUrl: url,
        ),
      ),
    ]);

    final response = await client.get('/about.html');

    expect(response.text, '<html><body>about</body></html>');
  });
}
