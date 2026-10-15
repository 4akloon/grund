import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:test/test.dart';
import 'package:users_app/users_app.dart' as annotated;

import '../helpers/explicit_users.dart';
import '../helpers/fake_adapter.dart';

/// The annotated application and the one written with the explicit API are
/// the same application: same graph, same routes, same answers.
void main() {
  const annotatedRoot = annotated.AppModule();
  const explicitRoot = ExplicitAppModule();

  /// Keys of the bindings of [module], sorted; routes classes differ in name
  /// only, so they are folded into one entry.
  List<String> bindingKeys(Module module) => [
    for (final binding in module.bindings)
      if ('${binding.key}'.endsWith('Routes') ||
          '${binding.key}' == 'ExplicitUsersApi')
        'routes'
      else
        '${binding.key}',
  ]..sort();

  List<String> exportsOf(Module module) =>
      [for (final export in module.exports) '$export']..sort();

  test('the auth modules bind and export the same keys', () {
    const generated = annotated.AuthModule();
    const written = ExplicitAuthModule();

    expect(bindingKeys(generated), bindingKeys(written));
    expect(exportsOf(generated), exportsOf(written));
    expect(generated.global, written.global);
  });

  test('the users modules bind and export the same keys', () {
    const generated = annotated.UsersModule();
    const written = ExplicitUsersModule();

    expect(bindingKeys(generated), bindingKeys(written));
    expect(exportsOf(generated), exportsOf(written));
    expect(generated.imports.length, written.imports.length);
  });

  test('both applications import the same modules', () {
    expect(annotatedRoot.imports, hasLength(explicitRoot.imports.length));
  });

  test('both applications serve the same routes and answers', () async {
    final generated = await TestApp.start(root: TestRoot(annotatedRoot));
    final written = await TestApp.start(root: TestRoot(explicitRoot));
    addTearDown(generated.close);
    addTearDown(written.close);
    final requests = <(String, String, Object?, Map<String, String>)>[
      ('GET', '/users', null, {}),
      ('GET', '/users?limit=1', null, {}),
      ('GET', '/users?limit=0', null, {}),
      ('GET', '/users/2', null, {}),
      ('GET', '/users/99', null, {}),
      ('GET', '/users/me', null, {'accept': 'a/b'}),
      ('GET', '/users/export', null, {}),
      ('POST', '/users', {'name': 'cy'}, {}),
      ('POST', '/users', {'name': 'cy'}, {'authorization': 'Bearer admin'}),
      ('POST', '/users', {'x': 1}, {'authorization': 'Bearer admin'}),
      ('DELETE', '/users/1', null, {'authorization': 'Bearer admin'}),
      ('PUT', '/users', null, {}),
    ];

    expect(_routes(generated), _routes(written));
    for (final (method, target, json, headers) in requests) {
      final a = await TestClient.of(
        generated,
      ).request(method, target, json: json, headers: headers);
      final b = await TestClient.of(
        written,
      ).request(method, target, json: json, headers: headers);
      expect(
        (a.status, a.text, _compared(a)),
        (b.status, b.text, _compared(b)),
        reason: '$method $target',
      );
    }
  });
}

/// The headers that must agree, as `name: value` lines in name order;
/// anything else (`date`, `server`, `content-length`) may legitimately differ.
const _comparedHeaders = ['content-type', 'www-authenticate', 'allow'];

String _compared(TestResponse response) => [
  for (final name in _comparedHeaders)
    if (response.headers[name] case final value?) '$name: $value',
].join('\n');

List<String> _routes(TestApp app) =>
    app.app.container.all<HttpServer>().single.routes;
