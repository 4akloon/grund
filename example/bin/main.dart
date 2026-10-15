import 'dart:async';
import 'dart:io';

import 'package:grund/grund.dart';
import 'package:tasks_api/tasks_api.dart';

/// Serves the tasks API until Ctrl+C or SIGTERM; see [ServerOptions.usage].
Future<void> main(List<String> arguments) async {
  final ServerOptions options;
  try {
    options = ServerOptions.parse(arguments, Platform.environment);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  // Listen for the signals before the port opens: `App.run` subscribes only
  // after the start, and a signal in between would kill the process with
  // -15 instead of closing gracefully. The future keeps the signal until
  // `run` asks for it.
  final stopRequested = StopSignals().wait();
  try {
    print(
      'Starting the ${options.style.name} module graph with '
      '${options.adapter.name} on http://localhost:${options.port}',
    );
    await TasksApp.create(options).run(
      only: Runners.fromArgs(arguments),
      signals: StopSignals(sources: [Stream.fromFuture(stopRequested)]),
    );
  } on RunnerError catch (error) {
    // A port in use arrives as the SocketException of the http runner.
    stderr.writeln('Cannot start: ${error.message}');
    // The pending signal subscription would keep the process alive.
    exit(1);
  }
}
