import 'package:code_builder/code_builder.dart';
import 'package:grund_generator/src/construct/construct.dart';
import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/construct/content_type.dart';
import 'package:grund_generator/src/construct/generated_unit.dart';
import 'package:grund_generator/src/construct/provider_claims.dart';
import 'package:grund_generator/src/emit/library_writer.dart';
import 'package:grund_generator/src/diagnostic/diagnostic.dart';
import 'package:grund_generator/src/diagnostic/diagnostic_code.dart';
import 'package:grund_generator/src/diagnostic/source_location.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

final _package = PackageModel(
  packageName: 'app',
  languageVersion: Version(3, 8, 0),
);

/// A construct with fixed output.
final class _FixedConstruct extends Construct {
  _FixedConstruct({this.diagnostics = const [], this.units = const []});

  final List<Diagnostic> diagnostics;

  final List<GeneratedUnit> units;

  int generated = 0;

  @override
  Iterable<Diagnostic> validate(PackageModel package, ProviderClaims claims) =>
      diagnostics;

  @override
  Iterable<GeneratedUnit> generate(
    PackageModel package,
    ProviderClaims claims,
  ) {
    generated++;
    return units;
  }
}

DartUnit _function(String name, int line) => DartUnit(
  name: name,
  spec: Method(
    (b) => b
      ..name = name
      ..returns = refer('int')
      ..lambda = true
      ..body = literalNum(line).code,
  ),
  origin: SourceLocation('lib/app.dart', line, 1),
);

Diagnostic _error(int line) => Diagnostic(
  DiagnosticCode.missingProvider,
  SourceLocation('lib/app.dart', line, 1),
  'No provider.',
);

void main() {
  _edges();
  test('joins the Dart units of every construct into one library', () {
    final result = GrundGenerator([
      _FixedConstruct(units: [_function('one', 1)]),
      _FixedConstruct(
        units: [
          _function('two', 2),
          const FileUnit(
            path: 'doc/api.json',
            contentType: ContentType.json,
            content: '{}',
          ),
        ],
      ),
    ]).generate(_package);

    expect(result.isSuccess, isTrue);
    expect(result.library, contains('int one() => 1;\n\nint two() => 2;\n'));
    expect([for (final f in result.files) f.path], ['doc/api.json']);
  });

  test('any diagnostic stops generation; they come sorted, once', () {
    final later = _FixedConstruct(units: [_function('one', 1)]);
    final result = GrundGenerator([
      _FixedConstruct(diagnostics: [_error(9), _error(2)]),
      _FixedConstruct(diagnostics: [_error(2)]),
      later,
    ]).generate(_package);

    expect(result.isSuccess, isFalse);
    expect(result.library, isNull);
    expect([for (final d in result.diagnostics) d.location.line], [2, 9]);
    expect(later.generated, 0);
  });

  test('two units with one name are a diagnostic', () {
    final result = GrundGenerator([
      _FixedConstruct(units: [_function('usersModule', 3)]),
      _FixedConstruct(units: [_function('usersModule', 8)]),
    ]).generate(_package);

    expect(
      result.diagnostics.single.toString(),
      'lib/app.dart:8:1: error: Generated name usersModule is used twice: for '
      'the declaration at lib/app.dart:3:1 and for this one. Rename one of '
      'them. [duplicate_generated_name]',
    );
  });
}

void _edges() {
  test('only files: the library holds just the header', () {
    final result = GrundGenerator([
      _FixedConstruct(
        units: [
          const FileUnit(
            path: 'a.txt',
            contentType: ContentType.text,
            content: 'a',
          ),
        ],
      ),
    ]).generate(_package);

    expect(result.isSuccess, isTrue);
    expect(result.files.single.contentType, ContentType.text);
    expect(result.library, startsWith(LibraryWriter.header));
  });

  test('no constructs generate an empty library', () {
    final result = const GrundGenerator([]).generate(_package);

    expect(result.isSuccess, isTrue);
    expect(result.files, isEmpty);
    expect(result.diagnostics, isEmpty);
  });

  test('a duplicate stops generation and reports every later copy', () {
    final result = GrundGenerator([
      _FixedConstruct(
        units: [_function('a', 1), _function('a', 2), _function('a', 3)],
      ),
    ]).generate(_package);

    expect(result.isSuccess, isFalse);
    expect([for (final d in result.diagnostics) d.location.line], [2, 3]);
    expect(result.library, isNull);
  });
}
