import 'package:grund_generator/src/diagnostic/diagnostic.dart';
import 'package:grund_generator/src/diagnostic/diagnostic_code.dart';
import 'package:grund_generator/src/diagnostic/source_location.dart';
import 'package:grund_generator/src/model/binding_key.dart';
import 'package:grund_generator/src/model/generated_names.dart';
import 'package:grund_generator/src/model/type_kind.dart';
import 'package:grund_generator/src/model/type_model.dart';
import 'package:test/test.dart';

const _users = 'package:app/users.dart';

TypeModel _type(
  String name, {
  bool nullable = false,
  List<TypeModel> args = const [],
}) => TypeModel(
  name: name,
  kind: TypeKind.interface,
  libraryUri: _users,
  typeArguments: args,
  isNullable: nullable,
);

void main() {
  test('a diagnostic prints as path:line:col: error: message [code]', () {
    final diagnostic = Diagnostic(
      DiagnosticCode.missingProvider,
      const SourceLocation('lib/users.dart', 3, 7),
      'No provider for Repo in module "users".',
    );

    expect(
      '$diagnostic',
      'lib/users.dart:3:7: error: No provider for Repo in module "users". '
          '[missing_provider]',
    );
  });

  test('diagnostics sort by path, line, column, then code', () {
    Diagnostic at(String path, int line, int column, DiagnosticCode code) =>
        Diagnostic(code, SourceLocation(path, line, column), 'm');
    final sorted = [
      at('lib/b.dart', 1, 1, DiagnosticCode.duplicateBinding),
      at('lib/a.dart', 9, 1, DiagnosticCode.duplicateBinding),
      at('lib/a.dart', 2, 5, DiagnosticCode.notInjectable),
      at('lib/a.dart', 2, 5, DiagnosticCode.missingProvider),
      at('lib/a.dart', 2, 1, DiagnosticCode.duplicateBinding),
    ]..sort();

    expect(
      [for (final d in sorted) '${d.location} ${d.code.id}'],
      [
        'lib/a.dart:2:1 duplicate_binding',
        'lib/a.dart:2:5 missing_provider',
        'lib/a.dart:2:5 not_injectable',
        'lib/a.dart:9:1 duplicate_binding',
        'lib/b.dart:1:1 duplicate_binding',
      ],
    );
  });

  test('type models compare by library, name, arguments and nullability', () {
    final list = _type('List', args: [_type('User')]);

    expect(list, _type('List', args: [_type('User')]));
    expect(list.display, 'List<User>');
    expect(_type('User', nullable: true).display, 'User?');
    expect(_type('User', nullable: true).nonNullable, _type('User'));
    expect(_type('User'), isNot(_type('User', nullable: true)));
    expect(_type('User').isDeclaredAs('User', _users), isTrue);
  });

  test('binding keys: a type with an optional name', () {
    final repo = BindingKey(_type('Repo'));
    final named = BindingKey(_type('Repo'), 'main');

    expect(repo, BindingKey(_type('Repo')));
    expect(repo, isNot(named));
    expect(named.display, "Repo('main')");
    expect(repo.display, 'Repo');
  });

  test('binding keys sort by display, then library', () {
    final keys = [
      BindingKey(_type('Repo'), 'b'),
      BindingKey(_type('Repo')),
      BindingKey(_type('Clock')),
    ]..sort();

    expect([for (final k in keys) k.display], ['Clock', 'Repo', "Repo('b')"]);
  });

  test('generated names derive from class names', () {
    expect(GeneratedNames.module('UsersModule'), r'$UsersModule');
  });

  test('the output of a library is its path with the suffix .g.dart', () {
    expect(
      GeneratedNames.outputPath('lib/src/users.dart'),
      'lib/src/users.g.dart',
    );
    expect(
      GeneratedNames.outputPath('lib/users_api.dart'),
      'lib/users_api.g.dart',
    );
  });
}
