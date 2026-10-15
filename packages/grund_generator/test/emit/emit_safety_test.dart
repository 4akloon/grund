import 'package:code_builder/code_builder.dart';
import 'package:grund_generator/src/emit/dart_string.dart';
import 'package:grund_generator/src/emit/import_allocator.dart';
import 'package:grund_generator/src/emit/library_writer.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

String _write(String packageName, List<Spec> declarations) =>
    LibraryWriter.write(
      packageName: packageName,
      languageVersion: Version(3, 8, 0),
      declarations: declarations,
    );

void main() {
  test('a library URI with a dollar and a quote is escaped in the import', () {
    final source = _write('app', [
      declareFinal('x')
          .assign(refer('Thing', r"package:app/a$b'c.dart").newInstance([]))
          .statement,
    ]);
    expect(source, contains(r"import 'package:app/a\$b\'c.dart' as i1;"));
  });

  test('a reference without a symbol is a StateError naming the library', () {
    expect(
      () =>
          ImportAllocator().allocate(const Reference(null, 'package:a/a.dart')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('package:a/a.dart'),
        ),
      ),
    );
  });

  test('a package name with a newline is rejected', () {
    expect(() => _write('app\nimport', []), throwsArgumentError);
    expect(() => _write('Bad-Name', []), throwsArgumentError);
    expect(_write('good_name1', []), contains('package:good_name1'));
  });

  test('C1 controls and lone surrogates are escaped', () {
    expect(
      DartString.literal('\u0080\u009f${String.fromCharCode(0xD800)}'),
      r"'\u{80}\u{9f}\u{d800}'",
    );
  });

  test('escapeUri escapes without quotes', () {
    expect(DartString.escape(r"a$b'c"), r"a\$b\'c");
  });
}
