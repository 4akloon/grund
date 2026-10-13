import 'package:code_builder/code_builder.dart';
import 'package:dartnest_generator/src/emit/constant_emitter.dart';
import 'package:dartnest_generator/src/emit/dart_string.dart';
import 'package:dartnest_generator/src/emit/library_writer.dart';
import 'package:dartnest_generator/src/emit/type_emitter.dart';
import 'package:dartnest_generator/src/model/constant_value.dart';
import 'package:dartnest_generator/src/model/type_kind.dart';
import 'package:dartnest_generator/src/model/type_model.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

const _app = 'package:app/roles.dart';

const _string = TypeModel(
  name: 'String',
  kind: TypeKind.interface,
  libraryUri: 'dart:core',
);

const _roles = TypeModel(
  name: 'Roles',
  kind: TypeKind.interface,
  libraryUri: _app,
);

String _library(List<Spec> declarations) => LibraryWriter.write(
  packageName: 'app',
  languageVersion: Version(3, 8, 0),
  declarations: declarations,
);

Spec _final(String name, Expression value) =>
    declareFinal(name).assign(value).statement;

void main() {
  // Review Focus 1: quotes, dollars, backslashes and line separators.
  test('user strings are escaped completely', () {
    expect(DartString.literal(r"it's $id \ ok"), r"'it\'s \$id \\ ok'");
    expect(DartString.literal('a\nb\tc\u0001 '), r"'a\nb\tc\u{1}\u{2028}'");
    expect(DartString.literal('привіт'), "'привіт'");
  });

  test('a library imports dartnest by name and the rest as i1, i2', () {
    final source = _library([
      _final('a', refer('Module', 'package:dartnest/src/di/module.dart')),
      _final('b', refer('Roles', _app)),
      _final('c', refer('Other', 'package:app/other.dart')),
      _final('d', refer('Roles', _app)),
    ]);

    expect(source, startsWith('${LibraryWriter.header}\n'));
    expect(source, contains("import 'package:app/other.dart' as i2;"));
    expect(source, contains("import 'package:app/roles.dart' as i1;"));
    expect(
      source,
      contains("import 'package:dartnest/dartnest.dart' as dartnest;"),
    );
    expect(source, contains('final a = dartnest.Module;'));
    expect(source, contains('final d = i1.Roles;'));
  });

  test('a constructor call is const at the top only', () {
    final roles = ObjectConstant(
      type: _roles,
      constructorName: '',
      positional: [
        ListConstant(_string, [StringConstant(r'a$')]),
      ],
      named: {'level': NumberConstant('2')},
    );

    expect(
      _library([_final('x', ConstantEmitter.expression(roles))]),
      contains(r"final x = const i1.Roles(<String>['a\$'], level: 2);"),
    );
    expect(
      _library([
        _final('x', ConstantEmitter.list([roles])),
      ]),
      contains(
        'final x = const [\n'
        r"  i1.Roles(<String>['a\$'], level: 2),"
        '\n];',
      ),
    );
  });

  test('references, enum values, types, maps and sets', () {
    final values = [
      const ReferenceConstant(name: 'dbUrl', libraryUri: _app),
      const ReferenceConstant(
        name: 'banned',
        libraryUri: _app,
        enclosingName: 'Status',
      ),
      const TypeConstant(_roles),
      MapConstant(_string, _string, [
        (const StringConstant('k'), const NullConstant()),
      ]),
      SetConstant(_string, [const BoolConstant(true)]),
    ];

    final source = _library([
      for (final (index, value) in values.indexed)
        _final('v$index', ConstantEmitter.expression(value)),
    ]);

    expect(source, contains('final v0 = i1.dbUrl;'));
    expect(source, contains('final v1 = i1.Status.banned;'));
    expect(source, contains('final v2 = i1.Roles;'));
    expect(source, contains("final v3 = const <String, String>{'k': null};"));
    expect(source, contains('final v4 = const <String>{true};'));
  });

  test('types keep arguments and nullability', () {
    const list = TypeModel(
      name: 'List',
      kind: TypeKind.interface,
      libraryUri: 'dart:core',
      typeArguments: [_roles],
      isNullable: true,
    );

    expect(
      _library([
        Method(
          (b) => b
            ..name = 't'
            ..returns = TypeEmitter.reference(list)
            ..lambda = true
            ..body = literalNull.code,
        ),
      ]),
      contains('List<i1.Roles>? t() => null;'),
    );
  });

  test('an unsupported constant never reaches generation', () {
    expect(
      () => ConstantEmitter.expression(const UnsupportedConstant('x')),
      throwsStateError,
    );
  });
}
