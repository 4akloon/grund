import 'package:test/test.dart';

import '../example/grund_http_generator_example.dart' as example;
import 'helpers/golden_files.dart';

void main() {
  test(
    'the example generates the committed files of the users fixture',
    () async {
      final files = await example.generatePackage(
        'users_app',
        'test/fixtures/users_app',
      );

      expect(files, GoldenFiles('test/fixtures/users_app').read());
    },
  );
}
