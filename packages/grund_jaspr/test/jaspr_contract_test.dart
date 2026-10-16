import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:test/test.dart';

/// Sets two cookies and shows the URL Jaspr saw.
final class _ContractPage extends StatelessComponent {
  const _ContractPage();

  @override
  Component build(BuildContext context) {
    context
      ..setCookie('a', '1')
      ..setCookie('b', '2');
    return Document(body: p([Component.text('url ${context.url}')]));
  }
}

/// The values of [name] in [headers], whatever the spelling of the name.
List<String> _values(Map<String, List<String>> headers, String name) => [
  for (final MapEntry(:key, :value) in headers.entries)
    if (key.toLowerCase() == name) ...value,
];

// What grund_jaspr relies on in Jaspr; a Jaspr upgrade that breaks one of
// these breaks the package.
void main() {
  setUpAll(Jaspr.initializeApp);

  test('a hand-made request renders a document with its URL', () async {
    final rendered = await renderComponent(
      const _ContractPage(),
      request: Request(
        'GET',
        Uri.parse('http://localhost/a/b?x=1'),
        handlerPath: '/',
      ),
    );

    expect(rendered.statusCode, 200);
    expect(String.fromCharCodes(rendered.body), contains('url /a/b?x=1'));
    expect(_values(rendered.headers, 'set-cookie'), hasLength(2));
    expect(_values(rendered.headers, 'content-type').single, contains('html'));
  });

  test('initializing Jaspr again keeps it initialized', () {
    Jaspr.initializeApp();

    expect(Jaspr.isInitialized, isTrue);
    expect(Jaspr.useIsolates, isFalse);
  });
}
