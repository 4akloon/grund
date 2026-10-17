import 'session.dart';
import 'session_store.dart';

/// Sessions in a map of this process: lost on restart, not shared between
/// processes.
///
/// An expired session is removed when it is read, and every [create]
/// removes all expired ones, so the map does not grow with sessions nobody
/// reads again.
final class InMemorySessionStore implements SessionStore {
  /// Creates an empty store; [now] is the clock (tests pass their own).
  InMemorySessionStore({this._now = DateTime.now});

  final DateTime Function() _now;
  final Map<String, Session> _sessions = {};

  @override
  Future<void> create(Session session) async {
    final now = _now();
    _sessions
      ..removeWhere((_, stored) => !stored.isLiveAt(now))
      ..[session.id] = session;
  }

  @override
  Future<Session?> read(String id) async {
    final session = _sessions[id];
    if (session == null || session.isLiveAt(_now())) return session;
    _sessions.remove(id);
    return null;
  }

  @override
  Future<void> delete(String id) async {
    _sessions.remove(id);
  }
}
