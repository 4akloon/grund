import 'package:grund_cli/src/generate/generation_report.dart';
import 'package:grund_cli/src/generate/generation_session.dart';
import 'package:grund_cli/src/generate/write_outcome.dart';
import 'package:test/test.dart';

import 'benchmark_sources.dart';
import '../test/helpers/temp_package.dart';

void main() {
  // The roadmap's targets: a cold run under 10 s and an incremental run
  // under 1 s on a package of about 200 files. The budget covers the
  // analyzer's re-resolution (about 700 ms of a change, measured) and the
  // generator (about 100 ms), not only the CLI; the incremental figure is the
  // median of three changes because single runs vary by 100 ms.
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
    final changes = <GenerationReport>[];
    for (var revision = 2; revision < 5; revision++) {
      final file = package.dir.write(
        BenchmarkSources.apiPath(7),
        BenchmarkSources.changedApi(7, revision: revision),
      );
      changes.add(await session.run(changed: [file]));
    }
    final milliseconds = [
      for (final change in changes) change.elapsed.inMilliseconds,
    ]..sort();
    final median = milliseconds[1];
    final timings =
        'cold ${cold.elapsedMilliseconds} ms, '
        'change median $median ms of $milliseconds';

    // The benchmark exists to show the measured times; printOnFailure would
    // hide them when it passes.
    // ignore: avoid_print
    print(timings);

    expect(
      first.outcome,
      WriteOutcome.written,
      reason: '${first.problemLines}',
    );
    expect(changes.map((c) => c.outcome), everyElement(WriteOutcome.written));
    expect(package.dir.read('lib/src/f7/api_api.g.dart'), contains("'/v4'"));
    expect(
      cold.elapsed,
      lessThan(const Duration(seconds: 10)),
      reason: timings,
    );
    expect(
      Duration(milliseconds: median),
      lessThan(const Duration(seconds: 1)),
      reason: timings,
    );
  });
}
