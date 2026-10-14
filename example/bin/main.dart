import 'dart:io';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest_io/dartnest_io.dart';
import 'package:dartnest_shelf/dartnest_shelf.dart';
import 'package:tasks_api/explicit.dart';
import 'package:tasks_api/tasks_api.dart';
import 'package:tasks_api/tasks_api.dartnest.dart';

/// Serves the tasks API until Ctrl+C; see [ServerOptions.usage].
Future<void> main(List<String> arguments) async {
  final ServerOptions options;
  try {
    options = ServerOptions.parse(arguments, Platform.environment);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  final app = await TasksApp.create(switch (options.style) {
    ModuleStyle.annotations => appModule,
    ModuleStyle.explicit => explicitAppModule,
  }, adapter: _adapter(options.adapter));
  await app.listen(port: options.port);
  print(
    'Serving the ${options.style.name} module graph with '
    '${options.adapter.name} on http://localhost:${options.port}',
  );
  // Ctrl+C closes gracefully: requests in flight finish, then main returns.
  await ProcessSignal.sigint.watch().first;
  await app.close();
}

HttpAdapter _adapter(AdapterKind kind) => switch (kind) {
  AdapterKind.io => IoAdapter(),
  AdapterKind.shelf => ShelfAdapter(),
};
