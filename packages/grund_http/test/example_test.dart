import 'package:test/test.dart';

import '../example/grund_http_example.dart' as example;

void main() {
  test('the example answers a GET, a POST and an unknown path in process', () {
    expect(
      example.callApi(),
      completion([
        'GET /greetings/grund -> 200 {"greeting":"Hello, grund!"}',
        'POST /greetings -> 201 {"name":"Ann"}',
        'GET /nowhere -> 404',
      ]),
    );
  });
}
