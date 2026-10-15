import 'package:code_builder/code_builder.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/src/emit/http_references.dart';
import 'package:test/test.dart';

const _hookRef = TypeModel(
  name: 'HookRef',
  kind: TypeKind.interface,
  libraryUri: 'package:grund_http/src/hook/hook_ref.dart',
  typeArguments: [
    TypeModel(
      name: 'RolesHook',
      kind: TypeKind.interface,
      libraryUri: 'package:app/hooks.dart',
    ),
  ],
);

String _source(ConstantValue value) =>
    '${ConstantEmitter.expression(HttpReferences.prefixed(value)).accept(DartEmitter())}';

void main() {
  test('a grund_http type gets the prefix and keeps its user arguments', () {
    const hook = ObjectConstant(type: _hookRef, constructorName: 'type');

    expect(_source(hook), 'const http.HookRef<RolesHook>.type()');
  });

  test('a grund_http constant inside an argument is prefixed too', () {
    const hook = ObjectConstant(
      type: TypeModel(
        name: 'Roles',
        kind: TypeKind.interface,
        libraryUri: 'package:app/hooks.dart',
      ),
      constructorName: '',
      positional: [
        ReferenceConstant(
          name: 'unauthorized',
          libraryUri: 'package:grund_http/src/http/status_code.dart',
          enclosingName: 'StatusCode',
        ),
      ],
    );

    expect(_source(hook), 'const Roles(http.StatusCode.unauthorized)');
  });

  test('a user declaration is left alone', () {
    const value = ReferenceConstant(
      name: 'high',
      libraryUri: 'package:app/hooks.dart',
      enclosingName: 'Priority',
    );

    expect(_source(value), 'Priority.high');
  });
}
