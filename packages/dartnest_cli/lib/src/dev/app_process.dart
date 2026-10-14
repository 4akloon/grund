import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The user's application, running in a child Dart VM with the VM service
/// on an ephemeral loopback port.
///
/// The child is one process (no development service), so [pid] is the
/// application's own `pid`. Its stdout and stderr are forwarded line by
/// line, except the VM service banner, which gives [serviceUri].
final class AppProcess {
  AppProcess._(this._process, this.serviceUri, this.exitCode);

  /// The flags of the child VM: the VM service on an ephemeral port of
  /// 127.0.0.1 with an authentication code in its URI, and no development
  /// service (DDS), which would run as a separate process.
  static const vmFlags = ['--enable-vm-service=0', '--no-dds'];

  static final _banner = RegExp(
    r'^The Dart VM service is listening on (http://\S+)$',
  );

  /// Starts `dart <vmFlags> <target> <arguments>` in [workingDirectory],
  /// forwarding the child's stdout lines to [out] and stderr lines to
  /// [err].
  static Future<AppProcess> start({
    required String target,
    required List<String> arguments,
    required String workingDirectory,
    required StringSink out,
    required StringSink err,
  }) async {
    final process = await Process.start(Platform.resolvedExecutable, [
      ...vmFlags,
      target,
      ...arguments,
    ], workingDirectory: workingDirectory);
    final serviceUri = Completer<Uri?>();
    final stdoutDone = _lines(process.stdout).listen((line) {
      final banner = serviceUri.isCompleted ? null : _banner.firstMatch(line);
      if (banner == null) {
        out.writeln(line);
      } else {
        serviceUri.complete(Uri.parse(banner[1] ?? ''));
      }
    }).asFuture<void>();
    final stderrDone = _lines(
      process.stderr,
    ).listen(err.writeln).asFuture<void>();
    final exitCode = Future.wait([stdoutDone, stderrDone]).then((_) async {
      if (!serviceUri.isCompleted) serviceUri.complete(null);
      return process.exitCode;
    });
    return AppProcess._(process, serviceUri.future, exitCode);
  }

  final Process _process;

  /// The URI of the child's VM service; `null` when the child exited
  /// without starting it.
  final Future<Uri?> serviceUri;

  /// The child's exit code, completed after its last output line was
  /// forwarded.
  final Future<int> exitCode;

  /// The process id of the child, the application's `pid`.
  int get pid => _process.pid;

  /// Ends the child and completes with its exit code: sends it `SIGTERM`
  /// (on Windows the process is terminated at once) and, when it is still
  /// running after [killGrace], `SIGKILL`.
  Future<int> stop({Duration killGrace = const Duration(seconds: 2)}) {
    _process.kill();
    return exitCode.timeout(
      killGrace,
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return exitCode;
      },
    );
  }

  static Stream<String> _lines(Stream<List<int>> bytes) => bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());
}
