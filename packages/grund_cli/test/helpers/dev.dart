import 'package:grund_cli/src/dev/app_launcher.dart';
import 'package:grund_cli/src/dev/dev_printer.dart';
import 'package:grund_cli/src/dev/dev_session.dart';
import 'package:grund_cli/src/dev/dev_target.dart';
import 'package:grund_cli/src/generate/generation_session.dart';
import 'package:test/test.dart';

import 'hello_app.dart';
import 'line_sink.dart';

/// A [DevSession] of the `hello` application, fed by a real
/// [GenerationSession] as `dev` feeds it; the application's output and
/// what the session prints go to [lines].
final class Dev {
  Dev._(this.app, this.lines, this.generation, this.session);

  /// Creates the application and starts it through the first run.
  static Future<Dev> start({
    AppLauncher? launcher,
    void Function(HelloApp app)? prepare,
    void Function()? onServing,
  }) async {
    final dev = await create(
      launcher: launcher,
      prepare: prepare,
      onServing: onServing,
    );
    await dev.change(const []);
    return dev;
  }

  /// Creates the application and the session without running anything.
  static Future<Dev> create({
    AppLauncher? launcher,
    void Function(HelloApp app)? prepare,
    void Function()? onServing,
  }) async {
    final app = await HelloApp.create();
    prepare?.call(app);
    final lines = LineSink();
    final generation = GenerationSession(app.package.root);
    addTearDown(generation.close);
    final session = DevSession(
      DevTarget(
        app.package.root,
        entry: app.package.dir.resolve('bin/main.dart'),
        arguments: const [],
      ),
      printer: DevPrinter('bin/main.dart', lines, lines),
      out: lines,
      launcher: launcher ?? const AppLauncher(),
      onServing: onServing,
    );
    addTearDown(session.stop);
    return Dev._(app, lines, generation, session);
  }

  final HelloApp app;
  final LineSink lines;
  final GenerationSession generation;
  final DevSession session;

  /// Generates after a change of the package files [relative] and applies
  /// the run, as the watch loop of `dev` does.
  Future<void> change(List<String> relative) async {
    final changed = [
      for (final path in relative) app.package.dir.resolve(path),
    ];
    final report = await generation.run(changed: changed);
    await session.apply(changed, report);
  }

  /// Waits for the next `listening on <port>` line of the application.
  Future<int> listening() async {
    final line = await lines.nextWhere((line) => HelloApp.portIn(line) != null);
    return HelloApp.portIn(line) ?? 0;
  }

  /// The answer of `GET /hello` on [port].
  static Future<Map<String, Object?>> hello(int port) async =>
      await HelloApp.get(port, '/hello') as Map<String, Object?>;
}
