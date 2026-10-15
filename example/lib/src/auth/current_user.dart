import 'role.dart';

/// The caller of a request, stored in the call scope by `ApiKeyHook`.
final class CurrentUser {
  /// A caller with [role].
  const CurrentUser(this.role);

  /// What the caller may do.
  final Role role;
}
