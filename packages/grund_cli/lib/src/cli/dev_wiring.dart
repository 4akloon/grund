import 'dart:async';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../bundle/client_bundler.dart';
import '../dev/dev_bundle.dart';
import '../dev/dev_printer.dart';
import '../dev/dev_session.dart';
import '../dev/dev_target.dart';
import '../dev/live_reload_hub.dart';
import '../dev/merged_watcher.dart';
import '../dev/terminal_keys.dart';
import '../generate/generation_session.dart';
import '../package/package_root.dart';
import '../watch/watch_loop.dart';
import 'cli_exit_code.dart';
import 'cli_failure.dart';
import 'grund_cli.dart';
import 'report_printer.dart';

/// Builds the parts `dev` runs: the session, the client bundle and the
/// watch loop that connects them.
final class DevWiring {
  /// Creates the wiring of [cli].
  DevWiring(this.cli);

  /// The command line `dev` belongs to.
  final GrundCli cli;

  /// The session of [target]; open pages reload once it serves.
  DevSession session(
    DevTarget target,
    LiveReloadHub liveReload,
    DevBundle? bundle,
  ) {
    if (TerminalKeys.isInteractive) {
      cli.out.writeln('Press r to hot reload, R to hot restart.');
    }
    return DevSession(
      target,
      printer: DevPrinter(
        target.package.display(target.entry),
        cli.out,
        cli.err,
      ),
      out: cli.out,
      // Open pages reload once the bundle is built too, also a failed build.
      onServing: bundle == null
          ? liveReload.broadcastReload
          : () => unawaited(
              bundle.settled.then((_) => liveReload.broadcastReload()),
            ),
    );
  }

  /// The bundle of the browser entry, or `null` when the package has none.
  DevBundle? bundle(PackageRoot package, ArgResults options) {
    final bundler = ClientBundler(
      package,
      entry: options.option('client-entry') ?? ClientBundler.defaultEntry,
      outputDirectory:
          options.option('output') ?? ClientBundler.defaultOutputDirectory,
      runner: cli.host.compileRunner,
    );
    if (bundler.hasEntry) return DevBundle(bundler, out: cli.out);
    if (options.wasParsed('client-entry')) {
      throw CliFailure(CliExitCode.usage, 'No ${bundler.entry}.');
    }
    return null;
  }

  /// The watcher and the loop that generates on a change and applies it.
  (Watcher, WatchLoop) watchLoop(
    PackageRoot package,
    String target,
    GenerationSession session,
    DevSession dev,
    DevBundle? bundle,
  ) {
    final (watcher, watched) = _watch(package, target);
    return (watcher, _loop(session, dev, bundle, watched));
  }

  WatchLoop _loop(
    GenerationSession session,
    DevSession dev,
    DevBundle? bundle,
    String watched,
  ) => WatchLoop.custom(
    generate: (changed) => session.run(changed: changed),
    watched: watched,
    printer: ReportPrinter(cli.out, cli.err),
    afterRun: (changed, report) {
      // In parallel with the reload; only sources that generate cleanly. The
      // first run (no changes) is covered by the initial build.
      if (changed.isNotEmpty && !report.hasProblems) bundle?.request();
      return dev.apply(changed, report);
    },
  );

  /// The watcher of `lib/` and of the directory of [target], and how the
  /// watched directories are printed.
  static (Watcher, String) _watch(PackageRoot package, String target) {
    final lib = DirectoryWatcher(package.libPath);
    if (p.isWithin(package.libPath, target)) return (lib, 'lib');
    final directory = p.dirname(target);
    return (
      MergedWatcher(package.path, [lib, DirectoryWatcher(directory)]),
      'lib/ and ${package.display(directory)}',
    );
  }
}
