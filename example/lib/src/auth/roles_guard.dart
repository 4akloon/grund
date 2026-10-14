import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'api_key_guard.dart';
import 'roles.dart';

/// Allows a handler only for the roles in its [Roles] metadata; runs after
/// [ApiKeyGuard], which stores the caller's role. A handler without
/// [Roles] is allowed for every caller.
@Injectable()
final class RolesGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) {
    final roles = context.metadata<Roles>();
    return roles == null ||
        roles.allowed.contains(context.items[ApiKeyGuard.roleItem]);
  }
}
