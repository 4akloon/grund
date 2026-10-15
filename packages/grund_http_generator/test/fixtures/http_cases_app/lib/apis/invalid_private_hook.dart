// A hook instance whose class is private to another library.
import 'package:grund_http/annotations.dart';

import 'private_hook_decl.dart';

/// An API that uses a hook it cannot name.
@Api('/y', use: [privHook])
final class PrivateHookApi {
  /// A route.
  @Get('/a')
  String a() => 'a';
}
