// The same API as hook_forms_short.dart, mixing the three entry forms.
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_http/grund_http.dart' as http;

import 'hook_forms_hooks.dart';

part 'hook_forms_mixed.g.dart';

/// Hooks in all forms, in the order of the other two libraries.
@Api('/forms', use: [HookRef<FormsAuthHook>.type(), FormsAuditHook()])
final class FormsApi {
  /// A route with hooks of both kinds.
  @Get('/a', use: [FormsRolesHook(2), HookRef<FormsAuthHook>.type()])
  String a() => 'a';
}
