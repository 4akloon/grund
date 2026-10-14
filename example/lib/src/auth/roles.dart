import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'role.dart';

/// Route metadata: the roles allowed to call a handler. `RolesGuard` reads
/// it.
final class Roles extends RouteMetadata {
  /// Allows [allowed].
  const Roles(this.allowed);

  /// The allowed roles.
  final List<Role> allowed;
}
