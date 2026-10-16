import 'package:test/test.dart';

import '../example/grund_auth_example.dart' as example;

void main() {
  test('the example signs in with a form and finds the user', () {
    expect(example.signIn(), completion(['303', '{"user":"ann"}']));
  });
}
