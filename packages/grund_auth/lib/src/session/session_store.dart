import 'session.dart';

/// Where sessions live between requests.
///
/// `InMemorySessionStore` is the one this package has: sessions end when
/// the process does. A durable store implements this interface.
abstract interface class SessionStore {
  /// Saves the new [session].
  Future<void> create(Session session);

  /// The session [id], or `null` when there is none (or it expired, for a
  /// store that tracks expiry).
  Future<Session?> read(String id);

  /// Removes the session [id]; nothing happens when there is none.
  Future<void> delete(String id);
}
