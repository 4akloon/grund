import 'dart:io';

import 'package:dartnest_cli/src/cli/cli_exit_code.dart';
import 'package:dartnest_cli/src/cli/cli_failure.dart';
import 'package:dartnest_cli/src/generate/output_writer.dart';
import 'package:dartnest_cli/src/generate/write_outcome.dart';
import 'package:dartnest_cli/src/package/package_root.dart';
import 'package:dartnest_generator/dartnest_generator.dart';
import 'package:test/test.dart';

import 'helpers/temp_dir.dart';

const _output = 'lib/shop.dartnest.dart';

const _source = '${LibraryWriter.header}\n\nlibrary;\n';

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

void main() {
  test('the library is written once and then left untouched', () {
    final (dir, writer) = _package();

    expect(writer.writeLibrary(_source), WriteOutcome.written);
    final modified = File(dir.resolve(_output)).lastModifiedSync();
    expect(writer.writeLibrary(_source), WriteOutcome.unchanged);

    expect(dir.read(_output), _source);
    expect(File(dir.resolve(_output)).lastModifiedSync(), modified);
    expect(dir.exists('$_output.tmp'), isFalse);
  });

  test('a changed library replaces the old one', () {
    final (dir, writer) = _package();
    writer.writeLibrary(_source);

    expect(writer.writeLibrary('$_source// v2\n'), WriteOutcome.written);
    expect(dir.read(_output), '$_source// v2\n');
  });

  // Review Focus 5: a hand-written file at the generated path.
  test('a file the generator did not write is never replaced', () {
    final (dir, writer) = _package();
    dir.write(_output, '// my own code\n');

    expect(() => writer.writeLibrary(_source), _cannotCreate('not generated'));
    expect(writer.deleteLibrary, _cannotCreate('not generated'));
    expect(dir.read(_output), '// my own code\n');
  });

  test('a stale generated library is deleted', () {
    final (dir, writer) = _package();
    writer.writeLibrary(_source);

    expect(writer.deleteLibrary(), WriteOutcome.deleted);
    expect(dir.exists(_output), isFalse);
    expect(writer.deleteLibrary(), WriteOutcome.none);
  });

  // Review Focus 2: the output cannot be written.
  test('a path that cannot be written is a cannot-create failure', () {
    final (dir, writer) = _package();
    Directory(dir.resolve('$_output.tmp')).createSync();

    expect(
      () => writer.writeLibrary(_source),
      _cannotCreate('Cannot write $_output'),
    );

    Directory(dir.resolve('$_output.tmp')).deleteSync();
    Directory(dir.resolve(_output)).createSync();
    expect(
      () => writer.writeLibrary(_source),
      _cannotCreate('Cannot write $_output'),
    );
  });

  test('other generated files stay inside the package', () {
    final (dir, writer) = _package();
    const unit = FileUnit(
      path: 'doc/api/openapi.json',
      contentType: ContentType.json,
      content: '{}',
    );
    const escaping = FileUnit(
      path: 'doc/../../outside.json',
      contentType: ContentType.json,
      content: '{}',
    );

    expect(writer.writeFile(unit), WriteOutcome.written);
    expect(writer.writeFile(unit), WriteOutcome.unchanged);
    expect(dir.read('doc/api/openapi.json'), '{}');
    expect(() => writer.writeFile(escaping), _cannotCreate('outside'));
  });
}
