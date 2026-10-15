// Hook entries that are neither a plain class nor an inline instance.
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart';

import 'hook_forms_hooks.dart';

/// A hook with a type parameter.
final class FormsBoxHook<T> extends HttpHook {
  /// Creates the hook.
  const FormsBoxHook();
}

/// An alias of a hook class.
typedef FormsAuthAlias = FormsAuthHook;

/// A constant instance shared by name.
const sharedHook = FormsRolesHook(3);

/// An API with a constant variable, an alias and a generic hook.
@Api('/more', use: [sharedHook, FormsAuthAlias, FormsBoxHook<int>])
final class MoreHooksApi {
  /// A route.
  @Get('/a')
  String a() => 'a';
}
