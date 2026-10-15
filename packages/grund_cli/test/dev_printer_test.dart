import 'package:grund_cli/src/dev/dev_printer.dart';
import 'package:grund_cli/src/dev/reload_result.dart';
import 'package:grund_cli/src/dev/served_changes.dart';
import 'package:test/test.dart';

/// What [print] wrote to stdout and stderr through a [DevPrinter].
(String, String) printed(void Function(DevPrinter printer) print) {
  final out = StringBuffer();
  final err = StringBuffer();
  print(DevPrinter('bin/main.dart', out, err));
  return ('$out', '$err');
}

const _elapsed = Duration(milliseconds: 180);

void main() {
  test('a reload with a reassemble counts and lists what changed', () {
    expect(
      printed(
        (printer) => printer.reloaded(
          const Reloaded(
            libraries: 3,
            elapsed: _elapsed,
            changes: ServedChanges(
              added: ['GET /hello/bye', 'GET /hello/hi'],
              removed: ['GET /hello/old'],
            ),
          ),
        ),
      ),
      (
        'Reloaded 3 libraries in 180 ms, 2 added, 1 removed.\n'
            '  + GET /hello/bye\n'
            '  + GET /hello/hi\n'
            '  - GET /hello/old\n',
        '',
      ),
    );
  });

  test('a reassemble that changed nothing says so in one line', () {
    expect(
      printed(
        (printer) => printer.reloaded(
          const Reloaded(
            libraries: 1,
            elapsed: _elapsed,
            changes: ServedChanges(),
          ),
        ),
      ),
      ('Reloaded 1 library in 180 ms, 0 added, 0 removed.\n', ''),
    );
  });

  test('a reload without a grund application has no change counts', () {
    expect(
      printed(
        (printer) =>
            printer.reloaded(const Reloaded(libraries: 1, elapsed: _elapsed)),
      ),
      ('Reloaded 1 library in 180 ms.\n', ''),
    );
  });

  test('a failed reassemble prints the error and the kept state', () {
    final (out, err) = printed(
      (printer) => printer.reloaded(
        const Reloaded(
          libraries: 1,
          elapsed: _elapsed,
          reassembleError: 'MissingProviderError: ...',
        ),
      ),
    );

    expect(out, isEmpty);
    expect(
      err,
      'MissingProviderError: ...\n'
      'Reloaded 1 library in 180 ms, but the application could not be '
      'reassembled; it keeps its previous modules.\n',
    );
  });

  test('a compile error keeps the previous code', () {
    expect(
      printed(
        (printer) => printer.reloaded(const ReloadFailed('x.dart: Error')),
      ),
      (
        '',
        'x.dart: Error\n'
            'Hot reload failed; bin/main.dart keeps running the previous code.\n',
      ),
    );
  });

  test('a rejected reload announces the restart with the reason', () {
    expect(
      printed(
        (printer) => printer.reloaded(const ReloadRejected('Limitation: x')),
      ),
      (
        'Restarting bin/main.dart: hot reload is not possible: Limitation: x.\n',
        '',
      ),
    );
  });

  test('start, exit and problems are one line each', () {
    final (out, err) = printed(
      (printer) => printer
        ..started(42, Uri.parse('http://127.0.0.1:1/a=/'))
        ..exited(255)
        ..waiting(isRunning: true)
        ..waiting(isRunning: false),
    );

    expect(
      out,
      'Started bin/main.dart (pid 42, VM service http://127.0.0.1:1/a=/).\n',
    );
    expect(
      err,
      'bin/main.dart exited with code 255; it starts again after the next '
      'change.\n'
      'bin/main.dart keeps running the previous code.\n'
      'bin/main.dart starts when the problems are fixed.\n',
    );
  });

  test('an unreachable VM service says the application was stopped', () {
    expect(printed((printer) => printer.unreachable()), (
      '',
      'bin/main.dart: could not connect to the VM service; stopped the '
          'application, it starts again after the next change.\n',
    ));
  });
}
