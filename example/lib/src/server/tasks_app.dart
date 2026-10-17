import 'package:grund/grund.dart';

import '../../explicit.dart';
import '../app_module.dart';
import 'module_style.dart';
import 'server_options.dart';
import 'serving_module.dart';

/// Creates the tasks application the same way for `bin/main.dart` and the
/// tests.
abstract final class TasksApp {
  /// The module graph [style] names.
  static Module graph(ModuleStyle style) => switch (style) {
    ModuleStyle.annotations => const AppModule(),
    ModuleStyle.explicit => const ExplicitAppModule(),
  };

  /// The application for [options], served over HTTP.
  static App create(ServerOptions options) => App(
    root: ServingModule(
      graph(options.style),
      options.adapter,
      address: options.address,
      port: options.port,
    ),
  );
}
