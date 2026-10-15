// Authentication: a bearer guard, a roles guard and their metadata.
import 'package:grund/grund.dart' hide Controller, Module;
import 'package:grund_annotations/grund_annotations.dart';

/// Route metadata: roles allowed to call a handler.
final class Roles extends RouteMetadata {
  /// Creates the metadata.
  const Roles(this.names);

  /// The role names.
  final List<String> names;
}

/// Accepts `authorization: Bearer <role>`; stores the role in `items`.
@Injectable()
final class AuthGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) {
    final header = context.header('authorization');
    if (header == null || !header.startsWith('Bearer ')) {
      throw const UnauthorizedException(
        headers: {'www-authenticate': 'Bearer'},
      );
    }
    context.items[#role] = header.substring('Bearer '.length);
    return true;
  }
}

/// Allows a handler only for the roles in its [Roles] metadata.
@Injectable()
final class RolesGuard implements Guard {
  @override
  bool canActivate(ExecutionContext context) {
    final roles = context.metadata<Roles>();
    return roles == null || roles.names.contains(context.items[#role]);
  }
}
