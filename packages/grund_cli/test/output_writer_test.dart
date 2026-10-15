import 'dart:io';

import 'package:grund_cli/src/cli/cli_exit_code.dart';
import 'package:grund_cli/src/cli/cli_failure.dart';
import 'package:grund_cli/src/generate/output_writer.dart';
import 'package:grund_cli/src/generate/write_outcome.dart';
import 'package:grund_cli/src/package/package_root.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import 'helpers/temp_dir.dart';

const _output = 'lib/src/app_module.g.dart';
const _api = 'lib/src/app_api.g.dart';

const _source = '${LibraryWriter.header}\n\nlibrary;\n';
const _apiSource = '${LibraryWriter.header}\n\npart of \'app.dart\';\n';

(TempDir, OutputWriter) _package() {
  final dir = TempDir.create();
  dir.write('pubspec.yaml', 'name: shop\n');
  Directory(dir.resolve('lib')).createSync();
  return (dir, OutputWriter(PackageRoot.open(dir.path)));
}

Matcher _cannotCreate(String message) => throwsA(
  isA<CliFailure>()
      .having((f) => f.exitCode, 'exitCode', CliExitCode.cannotCreate)
      .having((f) => f.message, 'message', contains(message)),
);

String? _cannotChmod() {
  if (Platform.isWindows) return 'file modes are not enforced on Windows';
  if (Process.runSync('id', ['-u']).stdout.toString().trim() == '0') {
    return 'root ignores file modes';
  }
  return null;
}

void main() {
  test('the files are written once and then left untouched', () {
    final (dir, writer) = _package();
    final files = {_output: _source, _api: _apiSource};

    final first = writer.sync(files);
    final modified = File(dir.resolve(_output)).lastModifiedSync();
    final second = writer.sync(files);

    expect(first.written, [_api, _output]);
    expect(first.outcome, WriteOutcome.written);
    expect(second.written, isEmpty);
    expect(second.outcome, WriteOutcome.unchanged);
    expect(dir.read(_output), _source);
    expect(dir.read(_api), _apiSource);
    expect(File(dir.resolve(_output)).lastModifiedSync(), modified);
    expect(dir.exists('$_output.tmp'), isFalse);
  });

  test('only the changed file is written again', () {
    final (dir, writer) = _package();
    writer.sync({_output: _source, _api: _apiSource});

    final synced = writer.sync({_output: _source, _api: '$_apiSource// v2\n'});

    expect(synced.written, [_api]);
    expect(dir.read(_api), '$_apiSource// v2\n');
  });

  // Review Focus 5: a hand-written file at a generated path.
  test('a file the generator did not write is never replaced', () {
    final (dir, writer) = _package();
    dir.write(_api, '// my own code\n');

    expect(
      () => writer.sync({_output: _source, _api: _apiSource}),
      _cannotCreate('not generated'),
    );
    expect(dir.read(_api), '// my own code\n');
  });

  test('a refused file stops the whole set before anything is written', () {
    final (dir, writer) = _package();
    dir.write(_output, '// my own code\n');

    expect(
      () => writer.sync({_api: _apiSource, _output: _source}),
      _cannotCreate('not generated'),
    );
    expect(dir.exists(_api), isFalse);
  });

  test('a stale generated file is deleted, a hand-written one is not', () {
    final (dir, writer) = _package();
    writer.sync({_output: _source, _api: _apiSource});
    dir.write('lib/other_api.g.dart', '// json_serializable or by hand\n');

    final synced = writer.sync({_output: _source});

    expect(synced.deleted, [_api]);
    expect(synced.outcome, WriteOutcome.written);
    expect(dir.exists(_api), isFalse);
    expect(dir.exists(_output), isTrue);
    expect(dir.exists('lib/other_api.g.dart'), isTrue);
  });

  test('an empty set deletes every stale file and then does nothing', () {
    final (dir, writer) = _package();
    writer.sync({_output: _source});

    final first = writer.sync({});
    final second = writer.sync({});

    expect(first.deleted, [_output]);
    expect(dir.exists(_output), isFalse);
    expect(second.outcome, WriteOutcome.none);
  });

  // Review Focus 2: the output cannot be written.
  test('a path that cannot be written is a cannot-create failure', () {
    final (dir, writer) = _package();
    Directory(dir.resolve('$_output.tmp')).createSync(recursive: true);

    expect(
      () => writer.sync({_output: _source}),
      _cannotCreate('Cannot write $_output'),
    );

    Directory(dir.resolve('$_output.tmp')).deleteSync();
    Directory(dir.resolve(_output)).createSync();
    expect(
      () => writer.sync({_output: _source}),
      _cannotCreate('Cannot write $_output'),
    );
  });

  test('generated files stay inside the package', () {
    final (dir, writer) = _package();

    expect(
      () => writer.sync({'doc/../../outside.json': '{}'}),
      _cannotCreate('outside'),
    );
    for (final path in ['/tmp/evil.json', r'..\evil.json', 'C:x.json']) {
      expect(() => writer.sync({path: '{}'}), _cannotCreate('outside'));
    }
    expect(dir.exists(r'..\evil.json'), isFalse);
  });

  test('a path spelled with dots is still the same file', () {
    final (dir, writer) = _package();
    dir.write(_output, '// my own code\n');

    expect(
      () => writer.sync({'lib/src/../src/app_module.g.dart': _source}),
      _cannotCreate(_output),
    );
    expect(dir.read(_output), '// my own code\n');
  });

  test('an existing temporary file is refused, not overwritten', () {
    final (dir, writer) = _package();
    dir.write('$_output.tmp', 'precious');

    expect(
      () => writer.sync({_output: _source}),
      _cannotCreate('delete it if no other grund run is writing'),
    );
    expect(dir.read('$_output.tmp'), 'precious');
    expect(dir.exists(_output), isFalse);
  });

  test('a failed rename removes the temporary file', () {
    final (dir, writer) = _package();
    Directory(dir.resolve(_output)).createSync(recursive: true);

    expect(
      () => writer.sync({_output: _source}),
      _cannotCreate('Cannot write $_output'),
    );
    expect(dir.exists('$_output.tmp'), isFalse);
  });

  test('an unwritable directory is a cannot-create failure', () {
    final (dir, writer) = _package();
    Directory(dir.resolve('lib/src')).createSync();
    Process.runSync('chmod', ['500', dir.resolve('lib/src')]);
    addTearDown(
      () => Process.runSync('chmod', ['700', dir.resolve('lib/src')]),
    );

    expect(
      () => writer.sync({_output: _source}),
      _cannotCreate('Cannot write $_output'),
    );
    expect(dir.exists('$_output.tmp'), isFalse);
  }, skip: _cannotChmod());

  test(
    'a stray temporary file of a later file stops the set before any write',
    () {
      final (dir, writer) = _package();
      dir.write('$_api.tmp', 'precious');

      expect(
        () => writer.sync({_output: _source, _api: _apiSource}),
        _cannotCreate('delete it if no other grund run is writing'),
      );

      expect(dir.exists(_output), isFalse);
      expect(dir.read('$_api.tmp'), 'precious');
    },
  );

  test('a failure midway reports what was written before it', () {
    final (dir, writer) = _package();
    const blocked = 'lib/ro/blocked_api.g.dart';
    dir.write('lib/ro/keep.txt', '');
    Process.runSync('chmod', ['500', dir.resolve('lib/ro')]);
    addTearDown(() => Process.runSync('chmod', ['700', dir.resolve('lib/ro')]));
    final touched = <String>[];

    expect(
      () => writer.sync({
        _output: _source,
        blocked: _apiSource,
      }, onTouched: touched.add),
      _cannotCreate('Cannot write $blocked'),
    );

    expect(touched, [_output]);
    expect(dir.exists(_output), isTrue);
    expect(dir.exists('$blocked.tmp'), isFalse);
  }, skip: _cannotChmod());

  test('a failed write leaves no temporary file behind', () {
    final (dir, writer) = _package();
    Directory(dir.resolve(_api)).createSync(recursive: true);

    expect(
      () => writer.sync({_api: _apiSource}),
      _cannotCreate('Cannot write'),
    );

    expect(dir.exists('$_api.tmp'), isFalse);
  });
}
