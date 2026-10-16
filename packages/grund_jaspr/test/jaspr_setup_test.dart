import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart';
import 'package:test/test.dart';

import 'helpers/pages.dart';
import 'helpers/pages_app.dart';

void main() {
  test('two applications in one process both render', () async {
    final first = await PagesApp.start([const JasprModule(app: UrlPage.new)]);
    final second = await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    expect((await first.get('/')).status, 200);
    expect((await second.get('/')).status, 200);
  });

  test('a component outside a page has no grund context', () async {
    await PagesApp.start([const JasprModule(app: UrlPage.new)]);

    final rendered = await renderComponent(const ScopelessPage());

    expect(String.fromCharCodes(rendered.body), contains('no scope'));
  });

  test('Jaspr initialized with useIsolates refuses to start', () async {
    Jaspr.initializeApp(useIsolates: true);
    addTearDown(Jaspr.initializeApp);

    await expectLater(
      PagesApp.start([const JasprModule(app: UrlPage.new)]),
      throwsA(isA<JasprSetupError>()),
    );
  });

  test('a page suffix with a leading dot refuses to start', () async {
    await expectLater(
      PagesApp.start([
        const JasprModule(
          app: UrlPage.new,
          config: JasprConfig(pageSuffixes: ['html', '.xml']),
        ),
      ]),
      throwsA(
        isA<JasprSetupError>().having(
          (e) => e.message,
          'message',
          contains('".xml"'),
        ),
      ),
    );
  });
}
