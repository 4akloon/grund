import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:test/test.dart';

import '../example/grund_example.dart' as example;

void main() {
  test('README example starts and resolves the greeting service', () async {
    final container = await Container.create(example.appModule);
    final greeter = container.root.get<example.Greeter>();
    expect(greeter.greet('grund'), 'Hello, grund! (via pg://localhost)');
  });

  test('the HTTP example answers through the injected greeter', () async {
    final app = await Application.create(example.httpModule);
    addTearDown(app.close);
    final response = await TestClient(app).get('/hello?name=you');
    expect(response.status, 200);
    expect(response.json, {'message': 'Hello, you! (via pg://localhost)'});
  });

  test('the HTTP example rejects a missing name with 400', () async {
    final app = await Application.create(example.httpModule);
    addTearDown(app.close);
    final response = await TestClient(app).get('/hello');
    expect(response.status, 400);
  });
}
