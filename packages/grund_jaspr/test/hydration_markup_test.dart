import 'dart:convert';

import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/server.dart';
import 'package:test/test.dart';

import 'helpers/client_samples.dart';
import 'helpers/sites.dart';

const _clients = JasprConfig(
  clients: ClientComponents([
    ClientComponent<Counter>(
      'counter',
      encode: Counter.toParams,
      decode: Counter.fromParams,
    ),
  ]),
);

const _hostile = 'a"b<c&d-->e\nfüg';

void main() {
  setUp(Jaspr.initializeApp);
  tearDown(Jaspr.initializeApp);

  test('a page with a counter has the markers and the bundle script', () async {
    final client = await startPublic([
      homePage(const Counter(3, 'n')),
    ], config: _clients);

    final html = (await client.get('/')).text;

    expect(html, contains('<!--@counter data='));
    expect(html, contains('<!--/@counter-->'));
    expect(
      html,
      contains(
        '<script src="/static/client/main.client.dart.js" defer></script>',
      ),
    );
  });

  test('the parameters survive the marker, whatever they hold', () async {
    final client = await startPublic([
      homePage(const Counter(3, _hostile)),
    ], config: _clients);

    final html = (await client.get('/')).text;

    final start =
        html.indexOf('<!--@counter data=') + '<!--@counter data='.length;
    final end = html.indexOf('-->', start);
    final payload = html.substring(start, end);
    expect(payload, isNot(contains('-->')));
    expect(html.indexOf('<!--/@counter-->'), greaterThan(end));
    final decoded = jsonDecode(
      payload
          .replaceAll('&gt;', '>')
          .replaceAll('&lt;', '<')
          .replaceAll('&quot;', '"')
          .replaceAll('&amp;', '&'),
    );
    expect(decoded, {'start': 3, 'label': _hostile});
  });

  test('without clients there are no markers and no script', () async {
    final client = await startPublic([homePage(const Counter(3, 'n'))]);

    final html = (await client.get('/')).text;

    expect(html, isNot(contains('<script')));
    expect(html, isNot(contains('<!--@')));
  });

  test('a subclass and an unregistered component have no markers', () async {
    final client = await startPublic([
      homePage(const Component.fragment([LoudCounter(1, 'l'), Plain()])),
    ], config: _clients);

    expect((await client.get('/')).text, isNot(contains('<!--@')));
  });

  test('an encode that is not JSON answers a 500 problem', () async {
    final client = await startPublic(
      [homePage(const _Dated())],
      config: JasprConfig(
        clients: ClientComponents([
          ClientComponent<_Dated>(
            'dated',
            encode: (_) => {'at': DateTime(2026)},
            decode: (_) => const _Dated(),
          ),
        ]),
      ),
    );

    final response = await client.get('/');

    expect(response.status, 500);
    expect(response.headers['content-type'], contains('problem+json'));
  });

  test('a duplicate name fails the start', () {
    const duplicate = JasprConfig(
      clients: ClientComponents([
        ClientComponent<Counter>('x', decode: Counter.fromParams),
        ClientComponent<Plain>('x', decode: _plain),
      ]),
    );

    expect(
      startPublic([homePage(const Plain())], config: duplicate),
      throwsA(isA<JasprSetupError>()),
    );
  });
}

Plain _plain(Map<String, Object?> _) => const Plain();

final class _Dated extends StatelessComponent {
  const _Dated();

  @override
  Component build(BuildContext context) => const Component.text('d');
}
