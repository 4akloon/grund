import 'package:grund_http/grund_http.dart';

import 'current_user.dart';
import 'role.dart';

/// Allows a route only for [role]; runs after `ApiKeyHook`, which stores
/// the caller. An instance hook: `use: [RolesHook(Role.editor)]`.
final class RolesHook extends HttpHook {
  /// Allows [role].
  const RolesHook(this.role);

  /// The role a route needs.
  final Role role;

  @override
  void before(HttpCtx c) {
    if (c<CurrentUser>().role != role) {
      throw ForbiddenException(
        message: 'This route needs the ${role.name} role.',
        code: 'role_required',
      );
    }
  }
}
