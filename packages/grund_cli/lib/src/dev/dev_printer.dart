import 'reload_result.dart';

/// Prints what `dev` does with the application at [target] (the entry
/// point relative to the package root): results to [out], failures and
/// why the previous code keeps running to [err].
final class DevPrinter {
  /// Creates the printer.
  const DevPrinter(this.target, this.out, this.err);

  /// The entry point, relative to the package root (`bin/main.dart`).
  final String target;

  /// Where results go.
  final StringSink out;

  /// Where failures go.
  final StringSink err;

  /// The application started as process [pid] with its VM service at
  /// [serviceUri].
  void started(int pid, Uri serviceUri) =>
      out.writeln('Started $target (pid $pid, VM service $serviceUri).');

  /// The application is restarted because of [reason].
  void restarting(String reason) => out.writeln('Restarting $target: $reason.');

  /// The application exited on its own with [code].
  void exited(int code) => err.writeln(
    '$target exited with code $code; it starts again after the next change.',
  );

  /// The VM service of the application could not be reached, so the
  /// application was stopped.
  void unreachable() => err.writeln(
    '$target: could not connect to the VM service; stopped the application, '
    'it starts again after the next change.',
  );

  /// The sources have problems: nothing was started or reloaded.
  void waiting({required bool isRunning}) => err.writeln(
    isRunning
        ? '$target keeps running the previous code.'
        : '$target starts when the problems are fixed.',
  );

  /// The outcome of a hot reload that did not need a restart.
  void reloaded(ReloadResult result) {
    switch (result) {
      case Reloaded(reassembleError: final error?):
        err
          ..writeln(error)
          ..writeln(
            '${_summary(result)}, but the application could not be '
            'reassembled; it keeps its previous modules.',
          );
      case Reloaded(:final changes?):
        out
          ..writeln(
            '${_summary(result)}, ${changes.added.length} added, '
            '${changes.removed.length} removed.',
          )
          ..writeAll([
            for (final entry in changes.added) '  + $entry\n',
            for (final entry in changes.removed) '  - $entry\n',
          ]);
      case Reloaded():
        out.writeln('${_summary(result)}.');
      case ReloadFailed(:final message):
        err
          ..writeln(message)
          ..writeln(
            'Hot reload failed; $target keeps running the previous code.',
          );
      case ReloadRejected(:final reason):
        restarting('hot reload is not possible: $reason');
    }
  }

  static String _summary(Reloaded result) =>
      'Reloaded ${_count(result.libraries, 'library', 'libraries')} '
      'in ${result.elapsed.inMilliseconds} ms';

  static String _count(int count, String one, [String? many]) =>
      '$count ${count == 1 ? one : many ?? '${one}s'}';
}
