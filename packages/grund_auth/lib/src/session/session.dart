/// A signed-in session: who it belongs to and until when it is valid.
///
/// The [id] is the opaque token in the session cookie; nothing else about
/// the session leaves the server.
final class Session {
  /// Creates the session.
  const Session({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.expiresAt,
  });

  /// The token of the session cookie.
  final String id;

  /// The user the session signs in.
  final String userId;

  /// When `Sessions.start` created it.
  final DateTime createdAt;

  /// When it ends; it is not extended by use.
  final DateTime expiresAt;

  /// Whether the session is still valid at [time].
  bool isLiveAt(DateTime time) => time.isBefore(expiresAt);
}
