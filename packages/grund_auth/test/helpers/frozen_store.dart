import 'package:grund_auth/grund_auth.dart';

/// A store that keeps what it is given, expired or not, and counts reads:
/// a store that does not track expiry.
final class FrozenStore implements SessionStore {
  /// The sessions, by id.
  final Map<String, Session> sessions = {};

  /// How often [read] was called.
  int reads = 0;

  @override
  Future<void> create(Session session) async {
    sessions[session.id] = session;
  }

  @override
  Future<Session?> read(String id) async {
    reads++;
    return sessions[id];
  }

  @override
  Future<void> delete(String id) async {
    sessions.remove(id);
  }
}
