import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:test/test.dart';

import 'helpers/pages_app.dart';
import 'helpers/real_server.dart';
import 'helpers/sites.dart';

List<Object> _modules() => [
  const JasprModule(),
  const PublicSiteModule(),
  const AdminSiteModule(),
  const HomePagesModule(),
  const UsersPagesModule(),
];

void main() {
  group('a guest on a guarded site', () {
    test('gets 401 for a trailing slash', () async {
      final client = await PagesApp.start(_modules().cast());

      expect((await client.get('/admin/users/')).status, 401);
      expect((await client.get('/admin/nope/')).status, 401);
    });

    test('gets 401 for HEAD of a page and of an unknown path', () async {
      final client = await PagesApp.start(_modules().cast());

      expect((await client.request('HEAD', '/admin/users')).status, 401);
      expect((await client.request('HEAD', '/admin/nope')).status, 401);
    });

    test('gets 401 for a doubled slash, as sent on the wire', () async {
      // TestClient normalises the target, so the real server is used.
      final server = await RealServer.start(_modules().cast());

      expect((await server.get('//admin/users')).status, 401);
      expect((await server.get('/admin//users')).status, 401);
      expect((await server.get('//admin/nope')).status, 401);
    });
  });
}
