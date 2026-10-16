import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_io/grund_io.dart';
import 'package:test/test.dart';

import 'account_api.dart';

/// [AccountApi] behind the global [SessionHook], started in process (no
/// socket); closed after the test.
abstract final class SessionApp {
  /// The client of the application with [config] and the store [store]
  /// creates.
  static Future<TestClient> start({
    SessionConfig config = const SessionConfig(),
    SessionStore Function() store = InMemorySessionStore.new,
  }) async {
    final app = await TestApp.start(
      root: _Root(SessionModule(config: config, store: store)),
    );
    addTearDown(app.close);
    return TestClient.of(app);
  }

  /// The value of the cookie [name] that [response] sets, or `null`.
  static String? cookie(TestResponse response, String name) {
    for (final header in response.headers.all('set-cookie')) {
      final pair = header.split(';').first;
      if (pair.startsWith('$name=')) return pair.substring(name.length + 1);
    }
    return null;
  }

  /// The `set-cookie` header of [response] for [name], or `null`.
  static String? header(TestResponse response, String name) => response.headers
      .all('set-cookie')
      .where((header) => header.startsWith('$name='))
      .firstOrNull;
}

final class _Root extends Module {
  const _Root(this._sessions);

  final SessionModule _sessions;

  @override
  List<Module> get imports => [
    const HttpModule(use: [HookRef<SessionHook>.type()]),
    const IoAdapterModule(),
    _sessions,
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<AccountApi>(
      (i) => AccountApi(i, i<Sessions>()),
      dependsOn: const [Key<Sessions>()],
    ),
  ];
}
