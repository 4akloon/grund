import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/testing.dart';
import 'package:grund_io/grund_io.dart';

/// Signs a name in with a form post and says who is signed in.
final class AccountApi extends HttpApi {
  /// Starts sessions through [_sessions].
  AccountApi(super.injector, this._sessions);

  final Sessions _sessions;

  @override
  List<Route> get routes => [
    Route.post('/login', _login),
    Route.get('/me', (c) => {'user': c.maybe<CurrentUser>()?.id}),
  ];

  Future<HttpResponse> _login(HttpCtx c) async {
    final name = (await c.form()).string('name', minLength: 1);
    // Check a password or another credential here before signing in.
    await _sessions.start(c, name);
    return HttpResponse.redirect(Uri.parse('/me'), status: StatusCode.seeOther);
  }
}

/// The root module: the server, sessions with their hook, and the API.
final class AppModule extends Module {
  /// Creates the module.
  const AppModule();

  @override
  List<Module> get imports => const [
    HttpModule(use: [HookRef<SessionHook>.type()]),
    IoAdapterModule(),
    // Plain http here; keep the default `secure: true` behind HTTPS.
    SessionModule(config: SessionConfig(secure: false)),
  ];

  @override
  List<Binding<Object>> get bindings => [
    Singleton<AccountApi>(
      (i) => AccountApi(i, i<Sessions>()),
      dependsOn: const [Key<Sessions>()],
    ),
  ];
}

/// Signs `ann` in, in process, and returns the status of the sign-in and
/// what `GET /me` answers with the session cookie.
Future<List<String>> signIn() async {
  final app = await TestApp.start(root: const AppModule());
  try {
    final client = TestClient.of(app);
    final login = await client.request(
      'POST',
      '/login',
      body: 'name=ann',
      headers: {'content-type': 'application/x-www-form-urlencoded'},
    );
    final cookie = (login.headers['set-cookie'] ?? '').split(';').first;
    final me = await client.get('/me', headers: {'cookie': cookie});
    return ['${login.status}', me.text];
  } finally {
    await app.close();
  }
}

/// Serves the API on port 8080 until Ctrl+C.
Future<void> main() => App(root: const AppModule()).run();
