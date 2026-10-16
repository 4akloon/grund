import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';

/// Signs in whoever names themselves, signs out, and says who is signed in.
final class AccountApi extends HttpApi {
  /// Creates the API.
  AccountApi(super.injector, this._sessions);

  final Sessions _sessions;

  @override
  List<Route> get routes => [
    Route.post('/login', _login),
    Route.post('/login-echo', (c) async {
      await _sessions.start(c, 'ann');
      return c.maybe<CurrentUser>()?.id ?? 'nobody';
    }),
    Route.post('/logout', (c) => _sessions.end(c)),
    Route.get('/me', (c) => c.maybe<CurrentUser>()?.id ?? 'nobody'),
    Route.post('/echo', (_) => 'ok'),
  ];

  Future<HttpResponse> _login(HttpCtx c) async {
    final name = (await c.form()).string('name');
    await _sessions.start(c, name);
    // The handler's own cookie, next to the session cookie of `start`.
    final flash = SetCookie('flash', 'signed-in').toHeader();
    return HttpResponse(
      StatusCode.seeOther,
      headers: HeaderMap.of({'location': '/', 'set-cookie': flash}),
    );
  }
}
