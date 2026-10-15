// An API whose hooks are written as classes and constant instances.
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

import 'hook_forms_hooks.dart';

part 'hook_forms_short.g.dart';

/// Hooks as classes and instances.
@Api('/forms', use: [FormsAuthHook, FormsAuditHook()])
final class FormsApi {
  /// A route with hooks of both kinds.
  @Get('/a', use: [FormsRolesHook(2), FormsAuthHook])
  String a() => 'a';
}
