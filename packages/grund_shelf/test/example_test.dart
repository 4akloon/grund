import 'package:test/test.dart';

import '../example/grund_shelf_example.dart' as example;

void main() {
  test('the README example serves a streamed body over loopback', () async {
    expect(await example.run(), '1\n2\n3\n');
  });
}
