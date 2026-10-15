import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';

import 'app_module_module.g.dart';
import 'auth.dart';
import 'users.dart';

/// The root of the users application.
@Module(imports: [AuthModule(), UsersModule()])
final class AppModule extends grund.Module with $AppModule {
  /// Creates the module.
  const AppModule();
}
