import 'package:dartnest_cli/src/dev/app_launcher.dart';
import 'package:dartnest_cli/src/dev/app_process.dart';
import 'package:dartnest_cli/src/dev/reload_client.dart';

/// An [AppLauncher] whose connect or close step throws, recording the
/// processes it started.
final class FailingLauncher extends AppLauncher {
  /// Creates a launcher that fails in [connectFails] or [closeFails].
  FailingLauncher({
    this.connectFails = false,
    this.connectNull = false,
    this.closeFails = false,
  });

  /// Whether [connect] throws.
  final bool connectFails;

  /// Whether [connect] finds the VM service gone.
  final bool connectNull;

  /// Whether [close] throws.
  final bool closeFails;

  /// Every process started so far.
  final started = <AppProcess>[];

  @override
  Future<AppProcess> start({
    required String target,
    required List<String> arguments,
    required String workingDirectory,
    required StringSink out,
    required StringSink err,
  }) async {
    final process = await super.start(
      target: target,
      arguments: arguments,
      workingDirectory: workingDirectory,
      out: out,
      err: err,
    );
    started.add(process);
    return process;
  }

  @override
  Future<ReloadClient?> connect(Uri serviceUri) async {
    if (connectFails) throw StateError('connect');
    return connectNull ? null : super.connect(serviceUri);
  }

  @override
  Future<void> close(ReloadClient client) =>
      closeFails ? Future.error(StateError('close')) : super.close(client);
}
