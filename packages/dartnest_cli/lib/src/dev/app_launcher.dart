import 'app_process.dart';
import 'reload_client.dart';

/// How a `DevSession` starts the application, connects to its VM service
/// and asks its dartnest applications to close. It is a seam: tests
/// replace it to make these steps fail.
class AppLauncher {
  /// Creates the launcher that really starts processes.
  const AppLauncher();

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
      ReloadClient.connect(serviceUri);

  /// Closes the dartnest applications behind [client].
  Future<void> close(ReloadClient client) => client.closeApplications();
}
