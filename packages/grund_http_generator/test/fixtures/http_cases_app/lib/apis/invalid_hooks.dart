// Every entry of use: that is not a hook, one per line.
import 'package:grund_http/annotations.dart';

import 'hook_forms_hooks.dart';

/// An API with a type that is not a hook.
@Api('/invalid-hooks', use: [NotAHook])
final class InvalidHooksApi {
  /// An instance that is not a hook.
  @Get('/a', use: [NotAHook()])
  String a() => 'a';

  /// A string.
  @Get('/b', use: ['hook'])
  String b() => 'b';

  /// Valid entries around an invalid one are still read.
  @Get('/c', use: [FormsAuthHook, 1, FormsRolesHook(1)])
  String c() => 'c';
}
