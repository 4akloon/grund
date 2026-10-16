import 'package:grund_http/grund_http.dart';

import '../current_user.dart';
import '../session/session_config.dart';
import '../session/sessions.dart';
import 'same_origin_hook.dart';

/// Puts the [CurrentUser] of a live session into the call scope; register
/// it once, globally:
///
/// ```dart
/// HttpModule(use: const [HookRef<SessionHook>.type()])
/// ```
///
/// A request without a session, or with an unknown, expired or forged
/// token, simply has no [CurrentUser]. With `SessionConfig.sameOrigin`
/// (the default) it first refuses unsafe cross-site requests the way
/// [SameOriginHook] does.
final class SessionHook extends HttpHook {
  /// Reads sessions through [sessions]; [config] says whether to check the
  /// origin.
  SessionHook(this._sessions, this._config);

  final Sessions _sessions;
  final SessionConfig _config;

  @override
  Future<void> before(HttpCtx c) async {
    if (_config.sameOrigin) const SameOriginHook().before(c);
    final session = await _sessions.current(c);
    if (session != null) c.set<CurrentUser>(CurrentUser(session.userId));
  }
}
