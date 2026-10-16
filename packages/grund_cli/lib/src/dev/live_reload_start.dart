import 'dart:io';

import '../cli/cli_exit_code.dart';
import '../cli/cli_failure.dart';
import 'live_reload_hub.dart';

/// Starts the live reload endpoint for `dev` and turns a bind failure into
/// the failure `dev` ends with.
abstract final class LiveReloadStart {
  /// The hub [start] returns; a [SocketException] (the loopback port could
  /// not be bound) becomes a [CliFailure] with the software exit code, not
  /// an unmapped exception.
  static Future<LiveReloadHub> run(
    Future<LiveReloadHub> Function() start,
  ) async {
    try {
      return await start();
    } on SocketException catch (error) {
      throw CliFailure(
        CliExitCode.software,
        'dev stopped: cannot start the live reload endpoint: $error',
      );
    }
  }
}
