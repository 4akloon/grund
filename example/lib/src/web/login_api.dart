import 'package:grund_auth/grund_auth.dart';
import 'package:grund_http/grund_http.dart';

/// Signs a visitor in and out; the forms of the pages post here.
///
/// The example trusts the name it is given. A real application checks a
/// password or another credential before [Sessions.start].
final class LoginApi extends HttpApi {
  /// Starts and ends sessions through [_sessions].
  LoginApi(super.injector, this._sessions);

  final Sessions _sessions;

  @override
  List<Route> get routes => [
    Route.post('/login', _login),
    Route.post('/logout', _logout),
  ];

  Future<HttpResponse> _login(HttpCtx c) async {
    final name = (await c.form()).string('name', minLength: 1, maxLength: 40);
    await _sessions.start(c, name);
    // The handler's own cookie travels next to the session cookie.
    final flash = SetCookie(
      'flash',
      'signed-in',
      attributes: const CookieAttributes(
        maxAge: Duration(minutes: 1),
        secure: false,
      ),
    );
    return HttpResponse(
      StatusCode.seeOther,
      headers: HeaderMap.of({'location': '/', 'set-cookie': flash.toHeader()}),
    );
  }

  Future<HttpResponse> _logout(HttpCtx c) async {
    await _sessions.end(c);
    return HttpResponse.redirect(Uri.parse('/'), status: StatusCode.seeOther);
  }
}
