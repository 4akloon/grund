import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'api_keys.dart';
import 'role.dart';

/// Lets a request through when its `x-api-key` header is a known key, and
/// stores the key's role for the guards after it.
@Injectable()
final class ApiKeyGuard implements Guard {
  /// Checks keys with [keys].
  ApiKeyGuard(this.keys);

  /// The known keys.
  final ApiKeys keys;

  /// The `ExecutionContext.items` key of the caller's [Role].
  static const roleItem = #role;

  @override
  bool canActivate(ExecutionContext context) {
    final key = context.header('x-api-key');
    final role = key == null ? null : keys.roleOf(key);
    if (role == null) {
      throw const UnauthorizedException(message: 'Send a valid x-api-key.');
    }
    context.items[roleItem] = role;
    return true;
  }
}
