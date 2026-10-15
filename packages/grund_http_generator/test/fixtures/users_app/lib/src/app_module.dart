import 'package:grund/grund.dart' as grund;
import 'package:grund/annotations.dart';

import 'app_module.g.dart';
import 'auth.dart';
import 'users_module.dart';

/// The root of the users application.
@Module(imports: [AuthModule(), UsersModule()])
final class AppModule extends grund.Module with $AppModule {
  /// Creates the module.
  const AppModule();
}
