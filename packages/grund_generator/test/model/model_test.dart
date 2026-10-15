import 'package:grund_generator/src/diagnostic/diagnostic.dart';
import 'package:grund_generator/src/diagnostic/diagnostic_code.dart';
import 'package:grund_generator/src/diagnostic/source_location.dart';
import 'package:grund_generator/src/model/constant_value.dart';
import 'package:grund_generator/src/model/generated_names.dart';
import 'package:grund_generator/src/model/provider_key.dart';
import 'package:grund_generator/src/model/route_model.dart';
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
      at('lib/b.dart', 1, 1, DiagnosticCode.duplicateRoute),
      at('lib/a.dart', 9, 1, DiagnosticCode.duplicateRoute),
      at('lib/a.dart', 2, 5, DiagnosticCode.notInjectable),
      at('lib/a.dart', 2, 5, DiagnosticCode.missingProvider),
      at('lib/a.dart', 2, 1, DiagnosticCode.duplicateRoute),
    ]..sort();

    expect(
      [for (final d in sorted) '${d.location} ${d.code.id}'],
      [
        'lib/a.dart:2:1 duplicate_route',
        'lib/a.dart:2:5 missing_provider',
        'lib/a.dart:2:5 not_injectable',
        'lib/a.dart:9:1 duplicate_route',
        'lib/b.dart:1:1 duplicate_route',
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

  test('provider keys: a type, or a token by value type and name', () {
    TokenKey token(String name, String expression) => TokenKey(
      valueType: _type('String'),
      name: name,
      expression: StringConstant(expression),
    );

    expect(TypeKey(_type('Repo')), TypeKey(_type('Repo')));
    expect(token('db.url', 'a'), token('db.url', 'b'));
    expect(token('db.url', 'a'), isNot(token('db.host', 'a')));
    expect(token('db.url', 'a').display, 'Token<String>(db.url)');
    expect(TypeKey(_type('Repo')).display, 'Repo');
  });

  test('route path parameters in declaration order', () {
    final route = RouteModel(
      method: 'GET',
      path: '/:org/users/:id/*',
      handlerName: 'find',
      returnType: TypeModel.voidType,
      location: const SourceLocation('lib/a.dart', 1, 1),
    );

    expect(route.pathParameters, ['org', 'id', '*']);
  });

  test('generated names derive from class names', () {
    expect(GeneratedNames.module('UsersModule'), 'usersModule');
    expect(GeneratedNames.module('Config'), 'configModule');
    expect(GeneratedNames.controller('UsersController'), 'usersController');
    expect(GeneratedNames.controller('Health'), 'healthController');
    expect(GeneratedNames.factory('UsersService'), '_createUsersService');
    expect(GeneratedNames.library('shop'), 'package:shop/shop.grund.dart');
  });
}
