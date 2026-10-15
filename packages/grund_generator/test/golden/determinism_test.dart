// Generation is a pure function of the package: neither a second run nor the
// order a driver passes libraries in changes a byte of the output. The class
// order inside a library is source order, fixed by the collector.
import 'dart:convert';
import 'dart:math';

import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

List<int> _bytes(PackageModel package) {
  final result = const GrundGenerator.core().generate(package);
  expect(result.diagnostics, isEmpty);
  return utf8.encode(result.library ?? fail('no library'));
}

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('users_app'));

  test('two runs over the same package are byte-identical', () async {
    final package = await fixture.collect();

    expect(_bytes(package), _bytes(package));
    expect(_bytes(await fixture.collect()), _bytes(package));
  });

  test('shuffled library orders give the same bytes', () async {
    final libraries = await fixture.libraries();
    final collector = PackageCollector('users_app', fixture.root);
    final expected = _bytes(collector.collect(libraries));

    for (var seed = 0; seed < 8; seed++) {
      final shuffled = [...libraries]..shuffle(Random(seed));
      expect(_bytes(collector.collect(shuffled)), expected, reason: '$seed');
    }
  });
}
