import 'package:grund_cli/src/generate/generation_session.dart';
import 'package:grund_cli/src/generate/write_outcome.dart';
import 'package:test/test.dart';

import 'benchmark_sources.dart';
import '../test/helpers/temp_package.dart';

void main() {
  // The roadmap's targets: a cold run under 10 s and an incremental run
  // under 1 s on a package of about 200 files.
  test('201 libraries: cold run under 10 s, a change under 1 s', () async {
    final package = await TempPackage.create(
      'bench',
      BenchmarkSources.files(50),
    );
    final cold = Stopwatch()..start();
    final session = GenerationSession(package.root);
    addTearDown(session.close);
    final first = await session.run();
    cold.stop();
    final file = package.dir.write(
      BenchmarkSources.controllerPath(7),
      BenchmarkSources.changedController(7),
    );
    final change = await session.run(changed: [file]);
    final timings =
        'cold ${cold.elapsedMilliseconds} ms, '
        'change ${change.elapsed.inMilliseconds} ms';

    // The benchmark exists to show the measured times; printOnFailure would
    // hide them when it passes.
    // ignore: avoid_print
    print(timings);

    expect(
      first.outcome,
      WriteOutcome.written,
      reason: '${first.problemLines}',
    );
    expect(change.outcome, WriteOutcome.written);
    expect(package.dir.read('lib/bench.grund.dart'), contains("'/v2'"));
    expect(
      cold.elapsed,
      lessThan(const Duration(seconds: 10)),
      reason: timings,
    );
    expect(
      change.elapsed,
      lessThan(const Duration(seconds: 1)),
      reason: timings,
    );
  });
}
