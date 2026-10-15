import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'api_key_hook.dart';
import 'auth_module_module.g.dart';

/// The API key check; modules that protect routes import it.
@Module(providers: [ApiKeyHook], exports: [ApiKeyHook])
final class AuthModule extends grund.Module with $AuthModule {
  /// Creates the module.
  const AuthModule();
}
