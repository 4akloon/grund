import '../di/injector.dart';
import 'reassemble_report.dart';

/// Something the application runs once the graph exists: an HTTP server, a
/// job worker, a message consumer.
///
/// A module binds its runners as singletons; `App` finds them with
/// `container.all<Runner>()`.
abstract class Runner {
  /// The name `only` selects the runner by.
  String get name;

  /// Validates the runner and builds what [start] needs, without serving.
  ///
  /// Called on every runner when the application starts, also on the ones
  /// that `only` leaves out, so that a broken configuration fails at once.
  Future<void> prepare(Injector injector) async {}

  /// Starts serving.
  Future<void> start(Injector injector);

  /// Stops serving and waits for the work in progress.
  Future<void> stop();

  /// Applies the new graph (hot reload) and returns what changed.
  ///
  /// By default the runner is stopped, prepared again and started. A runner
  /// that can swap its structures without a gap overrides this.
  Future<ReassembleReport> reassemble(Injector injector) async {
    await stop();
    await prepare(injector);
    await start(injector);
    return ReassembleReport.none;
  }
}
