// The hooks shared by the hook_forms_* libraries.
import 'package:grund/annotations.dart';
import 'package:grund_http/grund_http.dart';

/// A hook taken from the module graph.
@Injectable()
final class FormsAuthHook extends HttpHook {
  /// Creates the hook.
  const FormsAuthHook();
}

/// A hook given as a constant instance.
final class FormsRolesHook extends HttpHook {
  /// Creates the hook.
  const FormsRolesHook(this.level);

  /// The minimum level.
  final int level;
}

/// A common base of hooks, so that a hook is a subtype of `HttpHook` only
/// through it.
abstract class FormsBaseHook extends HttpHook {
  /// Creates the hook.
  const FormsBaseHook();
}

/// A hook that reaches `HttpHook` through [FormsBaseHook].
final class FormsAuditHook extends FormsBaseHook {
  /// Creates the hook.
  const FormsAuditHook();
}

/// A class that is not a hook.
final class NotAHook {
  /// Creates the value.
  const NotAHook();
}
