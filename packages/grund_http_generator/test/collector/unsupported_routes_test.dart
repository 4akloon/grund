import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    package = await FixturePackage.open(
      'http_cases_app',
    ).collect(['lib/unsupported_routes.dart']);
  });

  List<UnsupportedUse> uses(String element) => [
    for (final use in package.unsupportedUses)
      if (use.element == element) use,
  ];

  group('inherited annotations', () {
    test('an inherited route is recorded', () {
      expect(uses('InheritingApi').single.reason, contains('Base.inherited'));
    });

    test('a mixed-in route is recorded', () {
      expect(uses('MixingApi').single.reason, contains('RouteMixin.mixed'));
    });
  });

  test('a route path that is not a constant string is a problem', () {
    final route = package
        .extensionModel<HttpPackageModel>()!
        .apis
        .firstWhere((a) => a.type.name == 'PathApi')
        .routes
        .single;

    expect(route.problem, contains('constant string'));
  });
}
