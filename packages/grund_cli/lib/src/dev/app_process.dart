import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_command.dart';

/// The user's application, running in a child Dart VM with the VM service
/// on an ephemeral loopback port.
///
/// The child is one process (no development service), so [pid] is the
/// application's own `pid`. Its stdout and stderr are forwarded line by
/// line, except the VM service banner, which gives [serviceUri].
///
/// If the process running this class is itself killed with `SIGKILL`, the
/// child keeps running: Dart has no parent-death signal. The child's stdin
/// is never closed.
final class AppProcess {
  AppProcess._(this._process, this.serviceUri, this.exitCode);

  /// The flags of the child VM: the VM service on an ephemeral port of
  /// 127.0.0.1 with an authentication code in its URI, and no development
  /// service (DDS), which would run as a separate process.
  static const vmFlags = ['--enable-vm-service=0', '--no-dds'];

  static final _banner = RegExp(
    r'^The Dart VM service is listening on (http://\S+)$',
  );

  /// Starts `dart <vmFlags> <entry> <arguments>` of [command], forwarding
  /// the child's stdout lines to [out] and stderr lines to [err].
  static Future<AppProcess> start(
    AppCommand command, {
    required StringSink out,
    required StringSink err,
  }) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      [...vmFlags, command.entry, ...command.arguments],
      workingDirectory: command.workingDirectory,
      environment: command.environment,
    );
    final serviceUri = Completer<Uri?>();
    final stdoutDone = _lines(process.stdout).listen((line) {
      final banner = serviceUri.isCompleted ? null : _banner.firstMatch(line);
      if (banner == null) {
        out.writeln(line);
      } else {
        serviceUri.complete(Uri.parse(banner[1] ?? ''));
      }
    }).asFuture<void>();
    final stderrDone = _lines(process.stderr)
        .listen(err.writeln)
        .asFuture<void>();
    final exitCode = process.exitCode.then((code) async {
      // A grandchild may keep the pipes open after the child is gone, so
      // draining them is bounded.
      await Future.wait([stdoutDone, stderrDone])
          .timeout(const Duration(seconds: 1), onTimeout: () => const [])
          // The pipes of a child that is gone fail with I/O errors while
          // they are torn down; any other failure is a bug and surfaces.
          .catchError(
            (Object _) => const <void>[],
            test: (error) => error is IOException,
          );
      if (!serviceUri.isCompleted) serviceUri.complete(null);
      return code;
    });
    return AppProcess._(process, serviceUri.future, exitCode);
  }

  final Process _process;

  /// The URI of the child's VM service; `null` when the child exited
  /// without printing the banner (a child that fails early may still have
  /// printed it, depending on the SDK). It has no timeout of its own: callers race it
  /// against [exitCode].
  final Future<Uri?> serviceUri;

  /// The child's exit code, completed after its output was forwarded (the
  /// wait for the pipes to close is bounded: a grandchild may hold them).
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

  /// Ends the child at once with `SIGKILL`, without waiting.
  void kill() => _process.kill(ProcessSignal.sigkill);

  static Stream<String> _lines(Stream<List<int>> bytes) => bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());
}
