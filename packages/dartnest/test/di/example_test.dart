import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

import '../../example/di_example.dart' as example;

void main() {
  test('README example starts and resolves the greeting service', () async {
    final container = await Container.create(example.appModule);
    final greeter = container.root.get<example.Greeter>();
    expect(greeter.greet('dartnest'), 'Hello, dartnest! (via pg://localhost)');
  });
}
