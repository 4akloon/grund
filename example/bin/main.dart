import 'dart:async';
import 'dart:io';

import 'package:grund_io/grund_io.dart';
import 'package:grund_shelf/grund_shelf.dart';
import 'package:tasks_api/explicit.dart';
import 'package:tasks_api/tasks_api.dart';
import 'package:tasks_api/tasks_api.grund.dart';

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
  final adapter = switch (options.adapter) {
    AdapterKind.io => IoAdapter(),
    AdapterKind.shelf => ShelfAdapter(),
  };
  final app = await TasksApp.create(switch (options.style) {
    ModuleStyle.annotations => appModule,
    ModuleStyle.explicit => explicitAppModule,
  }, adapter: adapter);
  // Ctrl+C or SIGTERM closes gracefully: requests in flight finish, then main
  // returns.
  final stop = Completer<void>();
  final subscriptions = [
    ProcessSignal.sigint.watch().listen((_) => _once(stop)),
    if (!Platform.isWindows)
      ProcessSignal.sigterm.watch().listen((_) => _once(stop)),
  ];
  try {
    await app.listen(port: options.port);
  } on SocketException catch (error) {
    stderr.writeln('Cannot listen on port ${options.port}: ${error.message}');
    exitCode = 1;
    await _cancelAll(subscriptions);
    return;
  }
  _announce(options);
  await stop.future;
  await _cancelAll(subscriptions);
  await app.close();
}

Future<void> _cancelAll(List<StreamSubscription<ProcessSignal>> all) async {
  for (final subscription in all) {
    await subscription.cancel();
  }
}

void _once(Completer<void> stop) {
  if (!stop.isCompleted) stop.complete();
}

void _announce(ServerOptions options) => print(
  'Serving the ${options.style.name} module graph with '
  '${options.adapter.name} on http://localhost:${options.port}',
);
