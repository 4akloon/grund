import 'dart:io';

import 'package:test/test.dart';

import '../example/grund_generator_example.dart' as example;

void main() {
  test('the example generates the committed users_app library', () async {
    final generated = await example.generatePackage(
      'users_app',
      'test/fixtures/users_app',
    );
    final committed = File(
      'test/fixtures/users_app/lib/users_app.grund.dart',
    ).readAsStringSync();
    expect(generated, committed);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
