// The same API as hook_forms_short.dart, with HookRef constants.
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/grund_http.dart' as http;

import 'hook_forms_hooks.dart';

part 'hook_forms_ref.g.dart';

/// Hooks as `HookRef` constants.
@Api(
  '/forms',
  use: [
    HookRef<FormsAuthHook>.type(),
    HookRef<FormsAuditHook>.instance(FormsAuditHook()),
  ],
)
final class FormsApi {
  /// A route with hooks of both kinds.
  @Get(
    '/a',
    use: [
      HookRef<FormsRolesHook>.instance(FormsRolesHook(2)),
      HookRef<FormsAuthHook>.type(),
    ],
  )
  String a() => 'a';
}
