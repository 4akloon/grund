import 'package:test/test.dart';

import '../example/grund_jaspr_example.dart' as example;

void main() {
  test('the example renders a page with a value from DI', () {
    expect(
      example.renderTwice(),
      completion(['Visit number 1.', 'Visit number 2.']),
    );
  });
}
