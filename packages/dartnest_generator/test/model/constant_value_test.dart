import 'package:dartnest_generator/src/model/constant_value.dart';
import 'package:dartnest_generator/src/model/type_kind.dart';
import 'package:dartnest_generator/src/model/type_model.dart';
import 'package:test/test.dart';

const _string = TypeModel(
  name: 'String',
  kind: TypeKind.interface,
  libraryUri: 'dart:core',
);
const _bad = UnsupportedConstant('_Hidden is private');

void main() {
  test('plain values have nothing unsupported', () {
    const value = ObjectConstant(
      type: _string,
      constructorName: '',
      positional: [StringConstant('a'), NullConstant(), BoolConstant(true)],
      named: {'n': NumberConstant('1')},
    );

    expect(value.unsupported, isNull);
  });

  test('an unsupported constant reports itself', () {
    expect(_bad.unsupported, same(_bad));
  });

  test('unsupported is found inside a list', () {
    const value = ListConstant(_string, [StringConstant('a'), _bad]);

    expect(value.unsupported, same(_bad));
  });

  test('unsupported is found inside a set', () {
    const value = SetConstant(_string, [_bad]);

    expect(value.unsupported, same(_bad));
  });

  test('unsupported is found in a map key or value', () {
    const inKey = MapConstant(_string, _string, [(_bad, StringConstant('v'))]);
    const inValue = MapConstant(_string, _string, [
      (StringConstant('k'), _bad),
    ]);

    expect(inKey.unsupported, same(_bad));
    expect(inValue.unsupported, same(_bad));
  });

  test('unsupported is found in positional and named object arguments', () {
    const positional = ObjectConstant(
      type: _string,
      constructorName: '',
      positional: [_bad],
    );
    const named = ObjectConstant(
      type: _string,
      constructorName: '',
      named: {'x': _bad},
    );

    expect(positional.unsupported, same(_bad));
    expect(named.unsupported, same(_bad));
  });

  test('unsupported is found through nested collections', () {
    const value = ObjectConstant(
      type: _string,
      constructorName: '',
      positional: [
        ListConstant(_string, [
          MapConstant(_string, _string, [(StringConstant('k'), _bad)]),
        ]),
      ],
    );

    expect(value.unsupported, same(_bad));
  });
}
