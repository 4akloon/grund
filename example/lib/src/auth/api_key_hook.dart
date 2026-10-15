import 'package:grund/annotations.dart';
import 'package:grund_http/grund_http.dart';

import '../config/app_config.dart';
import 'current_user.dart';

/// Lets a request through when its `x-api-key` header is a known key, and
/// stores the caller for the hooks and handlers after it.
@Injectable()
final class ApiKeyHook extends HttpHook {
  /// Checks keys with [config].
  ApiKeyHook(this.config);

  /// The known keys.
  final AppConfig config;

  @override
  void before(HttpCtx c) {
    final key = c.headers.stringOrNull('x-api-key');
    final role = key == null ? null : config.apiKeys[key];
    if (role == null) {
      throw const UnauthorizedException(
        message: 'Send a valid x-api-key.',
        code: 'api_key_invalid',
      );
    }
    c.set<CurrentUser>(CurrentUser(role));
  }
}
