import 'package:grund_annotations/grund_annotations.dart';

import 'api_key_guard.dart';
import 'api_keys.dart';
import 'roles_guard.dart';

/// API keys and the guards that check them; modules that protect routes
/// import it.
@Module(
  id: 'auth',
  providers: [ApiKeys, ApiKeyGuard, RolesGuard],
  exports: [ApiKeyGuard, RolesGuard],
)
final class AuthModule {}
