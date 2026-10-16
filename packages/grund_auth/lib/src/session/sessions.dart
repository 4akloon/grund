import 'package:grund_http/grund_http.dart';

import '../cookie/set_cookie.dart';
import '../current_user.dart';
import 'session.dart';
import 'session_config.dart';
import 'session_store.dart';
import 'session_tokens.dart';

/// Starts, ends and finds the session of a request.
///
/// ```dart
/// Route.post('/login', (c) async {
///   final user = await accounts.verify(await c.form()); // yours
///   await sessions.start(c, user.id);
///   return HttpResponse.redirect(Uri.parse('/'), status: StatusCode.seeOther);
/// });
/// ```
final class Sessions {
  /// Keeps sessions in [store] with the cookie of [config].
  Sessions(this._store, this._config);

  final SessionStore _store;
  final SessionConfig _config;
  final SessionTokens _tokens = SessionTokens();

  /// Signs [userId] in: deletes the session the request came with, creates
  /// a new one under a fresh token (a token known before the sign-in never
  /// becomes valid: no session fixation), sets its cookie on [c]'s response
  /// and puts the [CurrentUser] in [c]'s call scope.
  Future<Session> start(HttpCtx c, String userId) async {
    await _forget(c);
    final now = DateTime.now();
    final session = Session(
      id: _tokens.next(),
      userId: userId,
      createdAt: now,
      expiresAt: now.add(_config.maxAge),
    );
    await _store.create(session);
    _setCookie(c, session.id, _config.maxAge);
    c.set<CurrentUser>(CurrentUser(userId));
    return session;
  }

  /// Signs out: deletes the session of the request and tells the browser
  /// to delete the cookie (an empty value with `Max-Age=0`).
  Future<void> end(HttpCtx c) async {
    await _forget(c);
    _setCookie(c, '', Duration.zero);
  }

  /// The live session of [c]'s cookie, or `null`: no cookie, a value that
  /// is not a token, an unknown or an expired session.
  Future<Session?> current(HttpCtx c) async {
    final token = _token(c);
    if (token == null) return null;
    final session = await _store.read(token);
    return session != null && session.isLiveAt(DateTime.now()) ? session : null;
  }

  Future<void> _forget(HttpCtx c) async {
    if (_token(c) case final token?) await _store.delete(token);
  }

  String? _token(HttpCtx c) {
    final token = c.cookies.stringOrNull(_config.cookieName);
    return token != null && SessionTokens.isWellFormed(token) ? token : null;
  }

  void _setCookie(HttpCtx c, String value, Duration maxAge) {
    final cookie = SetCookie(
      _config.cookieName,
      value,
      attributes: _config.attributes(maxAge: maxAge),
    );
    c.response.headers.add('set-cookie', cookie.toHeader());
  }
}
