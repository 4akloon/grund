import 'package:code_builder/code_builder.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

final _package = PackageModel(
  packageName: 'app',
  languageVersion: Version(3, 8, 0),
);

final _packageWithTasks = PackageModel(
  packageName: 'app',
  languageVersion: Version(3, 8, 0),
  libraryPaths: const ['lib/src/tasks.dart'],
);

const _library = 'lib/app.grund.dart';

/// A construct with fixed output.
final class _FixedConstruct extends Construct {
  _FixedConstruct({this.diagnostics = const [], this.units = const []});

  final List<Diagnostic> diagnostics;

  final List<GeneratedUnit> units;

  int generated = 0;

  @override
  String get name => 'fixed';

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

/// A unit kind the generator does not write.
final class _OtherUnit extends GeneratedUnit {
  const _OtherUnit();

  @override
  String get path => 'lib/other.txt';
}

Method _method(String name, int line) => Method(
  (b) => b
    ..name = name
    ..returns = refer('int')
    ..lambda = true
    ..body = literalNum(line).code,
);

LibraryUnit _function(String name, int line, {String path = _library}) =>
    LibraryUnit(
      path: path,
      name: name,
      spec: _method(name, line),
      origin: SourceLocation('lib/app.dart', line, 1),
    );

Diagnostic _error(int line) => Diagnostic(
  DiagnosticCode.missingProvider,
  SourceLocation('lib/app.dart', line, 1),
  'No provider.',
);

void main() {
  _edges();
  _parts();
  test('joins the library units of every construct into one library', () {
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
    expect(
      result.files[_library],
      contains('int one() => 1;\n\nint two() => 2;\n'),
    );
    expect(result.files.keys, ['doc/api.json', _library]);
    expect(result.files['doc/api.json'], '{}');
  });

  test('any diagnostic stops generation; they come sorted, once', () {
    final later = _FixedConstruct(units: [_function('one', 1)]);
    final result = GrundGenerator([
      _FixedConstruct(diagnostics: [_error(9), _error(2)]),
      _FixedConstruct(diagnostics: [_error(2)]),
      later,
    ]).generate(_package);

    expect(result.isSuccess, isFalse);
    expect(result.files, isEmpty);
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
  test('only files: no library is written', () {
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
    expect(result.files['a.txt'], 'a');
    expect(result.files.keys, ['a.txt']);
  });

  test('no constructs generate no files', () {
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
    expect(result.files, isEmpty);
  });
}

void _parts() {
  test('library units of another path form a library of their own', () {
    final result = GrundGenerator([
      _FixedConstruct(
        units: [
          _function('a', 1, path: 'lib/x_module.g.dart'),
          _function('a', 2),
        ],
      ),
    ]).generate(_package);

    expect(result.isSuccess, isTrue);
    expect(result.files['lib/x_module.g.dart'], contains('int a() => 1;'));
    expect(result.files[_library], contains('int a() => 2;'));
  });

  test('part units form a part of their host without imports', () {
    final result = GrundGenerator([
      _FixedConstruct(
        units: [
          PartUnit(
            path: 'lib/src/tasks_api.g.dart',
            hostPath: 'lib/src/tasks.dart',
            name: 'tasks',
            spec: Method(
              (b) => b
                ..name = 'tasks'
                ..returns = refer('Task', 'package:app/src/task.dart')
                ..lambda = true
                ..body = const Code('throw 0'),
            ),
            origin: const SourceLocation('lib/src/tasks.dart', 1, 1),
          ),
        ],
      ),
    ]).generate(_packageWithTasks);
    final part = result.files['lib/src/tasks_api.g.dart'];

    expect(part, startsWith(LibraryWriter.header));
    expect(part, contains("part of 'tasks.dart';"));
    expect(part, contains('Task tasks() => throw 0;'));
    expect(part, isNot(contains('import')));
  });

  test('units of different kinds on one path are a programming error', () {
    GenerationResult generate(List<GeneratedUnit> units) =>
        GrundGenerator([_FixedConstruct(units: units)]).generate(_package);

    expect(
      () => generate([
        _function('a', 1),
        const FileUnit(
          path: _library,
          contentType: ContentType.text,
          content: '',
        ),
      ]),
      throwsStateError,
    );
    expect(() => generate([const _OtherUnit()]), throwsStateError);
  });

  group('the host of a part', () {
    PartUnit part({required String path, required String hostPath}) => PartUnit(
      path: path,
      hostPath: hostPath,
      name: 'tasks',
      spec: Method(
        (b) => b
          ..name = 'tasks'
          ..returns = refer('int')
          ..lambda = true
          ..body = const Code('1'),
      ),
      origin: const SourceLocation('lib/src/tasks.dart', 1, 1),
    );

    GenerationResult generate(
      PackageModel package,
      List<GeneratedUnit> units,
    ) => GrundGenerator([_FixedConstruct(units: units)]).generate(package);

    test('is a source library of the package', () {
      expect(
        () => generate(_package, [
          part(path: 'lib/a_api.g.dart', hostPath: 'lib/a.dart'),
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('lib/a.dart'),
          ),
        ),
      );
    });

    test('may be a generated library', () {
      final result = generate(_package, [
        _function('a', 1, path: 'lib/a_module.g.dart'),
        part(path: 'lib/a_api.g.dart', hostPath: 'lib/a_module.g.dart'),
      ]);

      expect(result.isSuccess, isTrue);
    });

    test('is not the part itself', () {
      expect(
        () => generate(_packageWithTasks, [
          part(path: 'lib/src/tasks.dart', hostPath: 'lib/src/tasks.dart'),
        ]),
        throwsStateError,
      );
    });
  });
}
