import 'package:grund/grund.dart' as grund;
import 'package:grund/annotations.dart';
import 'package:grund_http/grund_http.dart';

import 'auth_module.g.dart';
import 'users.dart';

/// The role of the caller, set by [AuthHook].
final class CurrentRole {
  /// Creates the value.
  CurrentRole(this.name);

  /// The role.
  final String name;
}

/// Accepts `authorization: Bearer <role>` and sets [CurrentRole].
@Injectable()
final class AuthHook extends HttpHook {
  /// Creates the hook.
  const AuthHook();

  @override
  void before(HttpCtx c) {
    final header = c.headers.stringOrNull('authorization');
    if (header == null || !header.startsWith('Bearer ')) {
      throw const UnauthorizedException(
        headers: {'www-authenticate': 'Bearer'},
      );
    }
    c.set<CurrentRole>(CurrentRole(header.substring('Bearer '.length)));
  }
}

/// Allows a route only for the given roles; the roles are the hook's
/// parameters, so it is used as a constant instance.
final class RolesHook extends HttpHook {
  /// Creates the hook.
  const RolesHook(this.names);

  /// The roles that may pass.
  final List<String> names;

  @override
  void before(HttpCtx c) {
    if (!names.contains(c<CurrentRole>().name)) {
      throw const ForbiddenException(code: 'role_not_allowed');
    }
  }
}

/// Translates [UserMissing] into a 404.
@Injectable()
final class UserMissingHook extends HttpHook {
  /// Creates the hook.
  const UserMissingHook();

  @override
  HttpResponse? onError(HttpCtx c, Object error, StackTrace stack) {
    if (error is UserMissing) {
      throw NotFoundException(
        message: 'No user ${error.id}',
        code: 'user_not_found',
      );
    }
    return null;
  }
}

/// The hooks every API of the application may use.
@Module(
  providers: [AuthHook, UserMissingHook],
  exports: [AuthHook, UserMissingHook],
  global: true,
)
final class AuthModule extends grund.Module with $AuthModule {
  /// Creates the module.
  const AuthModule();
}
