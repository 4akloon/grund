import 'app_process.dart';
import 'reload_client.dart';
import 'reload_timeouts.dart';

/// How a `DevSession` starts the application, connects to its VM service
/// and asks its dartnest applications to close. It is a seam: tests
/// replace it to make these steps fail.
class AppLauncher {
  /// Creates the launcher that really starts processes; its connections use
  /// [timeouts].
  const AppLauncher({this.timeouts = const ReloadTimeouts()});

  /// How long the connections it makes wait for the VM service.
  final ReloadTimeouts timeouts;

  /// Starts the application; see [AppProcess.start].
  Future<AppProcess> start({
    required String target,
    required List<String> arguments,
    required String workingDirectory,
    required StringSink out,
    required StringSink err,
  }) => AppProcess.start(
    target: target,
    arguments: arguments,
    workingDirectory: workingDirectory,
    out: out,
    err: err,
  );

  /// Connects to the VM service at [serviceUri]; see [ReloadClient.connect].
  Future<ReloadClient?> connect(Uri serviceUri) =>
      ReloadClient.connect(serviceUri, timeouts: timeouts);

  /// Closes the dartnest applications behind [client].
  Future<void> close(ReloadClient client) => client.closeApplications();
}
