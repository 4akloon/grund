import 'package:code_builder/code_builder.dart';
import 'package:grund_generator/src/emit/constant_emitter.dart';
import 'package:grund_generator/src/emit/dart_string.dart';
import 'package:grund_generator/src/emit/library_writer.dart';
import 'package:grund_generator/src/model/constant_value.dart';
import 'package:grund_generator/src/model/type_kind.dart';
import 'package:grund_generator/src/model/type_model.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

const _string = TypeModel(
  name: 'String',
  kind: TypeKind.interface,
  libraryUri: 'dart:core',
);

const _guard = TypeModel(
  name: 'Guard',
  kind: TypeKind.interface,
  libraryUri: 'package:app/guard.dart',
);

String _x(Expression value) => LibraryWriter.write(
  packageName: 'app',
  languageVersion: Version(3, 8, 0),
  declarations: [declareFinal('x').assign(value).statement],
);

void main() {
  test('carriage returns, DEL and paragraph separators are escaped', () {
    expect(DartString.literal('\r\u007f '), r"'\r\u{7f}\u{2029}'");
    expect(DartString.literal(''), "''");
  });

  test('astral characters pass through whole', () {
    expect(DartString.literal('a\u{1F600}'), "'a\u{1F600}'");
  });

  test('null, bool and number constants', () {
    expect(
      _x(ConstantEmitter.expression(const NullConstant())),
      contains('null'),
    );
    expect(
      _x(ConstantEmitter.expression(const BoolConstant(false))),
      contains('false'),
    );
    expect(
      _x(ConstantEmitter.expression(const NumberConstant('0.5'))),
      contains('0.5'),
    );
  });

  test('named constructors are const at the top, plain inside', () {
    const inner = ObjectConstant(type: _guard, constructorName: 'strict');
    const outer = ObjectConstant(
      type: _guard,
      constructorName: 'wrap',
      positional: [inner],
    );

    expect(
      _x(ConstantEmitter.expression(outer)),
      contains('const i1.Guard.wrap(i1.Guard.strict())'),
    );
  });

  test('collections nested in a constructor call are not const', () {
    final call = ObjectConstant(
      type: _guard,
      constructorName: '',
      positional: [
        SetConstant(_string, [const StringConstant('s')]),
        MapConstant(_string, _string, [
          (const StringConstant('k'), const StringConstant('v')),
        ]),
      ],
    );

    final source = _x(ConstantEmitter.expression(call));

    expect(source, contains("<String>{'s'}"));
    expect(source, contains("<String, String>{'k': 'v'}"));
    expect(source, isNot(contains('const <')));
  });

  test('top-level collections are const', () {
    expect(
      _x(ConstantEmitter.expression(ListConstant(_string, const []))),
      contains('const <String>[]'),
    );
  });
}
