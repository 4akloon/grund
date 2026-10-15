import 'package:grund/annotations.dart';
import 'package:test/test.dart';

void main() {
  test('Module defaults to an empty, non-global module', () {
    const module = Module();

    expect(module.imports, isEmpty);
    expect(module.providers, isEmpty);
    expect(module.exports, isEmpty);
    expect(module.global, isFalse);
  });

  test('Injectable and Provides default to the singleton scope', () {
    expect(const Injectable().scope, Scope.singleton);
    expect(const Provides().scope, Scope.singleton);
    expect(const Injectable(scope: Scope.call).scope, Scope.call);
    expect(const Provides(scope: Scope.transient).scope, Scope.transient);
  });

  test('Named keeps its name', () {
    expect(const Named('primary').name, 'primary');
  });

  test('Bind has the interface and the implementation as type arguments', () {
    expect(
      const Bind<Object, String>().runtimeType.toString(),
      'Bind<Object, String>',
    );
  });
}
