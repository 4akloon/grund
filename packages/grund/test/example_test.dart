import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:test/test.dart';

import '../example/grund_example.dart';

void main() {
  test('the example greets on start and says goodbye on close', () async {
    expect(await greetOnce(), ['Hello, grund!', 'Goodbye.']);
  });

  test('TestApp resolves the example services without running them', () async {
    final lines = <String>[];
    final app = await TestApp.start(root: GreetingModule(lines));
    addTearDown(app.close);

    expect(app<Greeter>().greet('you'), 'Hello, you!');
    expect(lines, isEmpty);
  });

  test('an override replaces the greeter of the example', () async {
    final app = await TestApp.start(
      root: GreetingModule([]),
      overrides: [
        Singleton<Greeter>((i) => Greeter('Hi'), dependsOn: const []),
      ],
    );
    addTearDown(app.close);

    expect(app<Greeter>().greet('you'), 'Hi, you!');
  });
}
