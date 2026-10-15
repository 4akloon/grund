import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'auth.dart';
import 'users.dart';
import 'users_api.dart';
import 'users_module.g.dart';

/// Users: bindings and settings.
@Module(
  imports: [AuthModule()],
  providers: [UsersService, UsersApi, Bind<UserStore, InMemoryUserStore>()],
  exports: [UsersService, grund.Key<StringBuffer>('audit')],
)
final class UsersModule extends grund.Module with $UsersModule {
  /// Creates the module.
  const UsersModule();

  static int _requests = 0;

  /// The settings.
  @Provides()
  static UsersConfig config() => const UsersConfig(greeting: 'hello');

  /// Where changes are written; a singleton may be created asynchronously.
  @Provides()
  @Named('audit')
  static Future<StringBuffer> audit() async => StringBuffer();

  /// One value per call.
  @Provides(scope: Scope.call)
  static RequestInfo requestInfo() => RequestInfo(++_requests);
}
