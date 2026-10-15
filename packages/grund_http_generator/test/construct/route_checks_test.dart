import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/src/construct/route_paths.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';
import '../helpers/fixture_package.dart';

void main() {
  late PackageModel cases; // Set in setUpAll.

  setUpAll(() async {
    cases = await FixturePackage.open(
      'http_cases_app',
    ).collect(['lib/apis/tasks.dart', 'lib/apis/invalid.dart']);
  });

  test('the invalid api routes report their stable codes', () {
    expect(
      GraphModels.codes(cases).toSet(),
      containsAll([
        'invalid_route_handler',
        'parameter_without_source',
        'missing_from_json',
        'unknown_path_parameter',
        'invalid_handler_parameter',
        'invalid_validator',
        'unsupported_return_type',
        'stream_return_reserved',
        'duplicate_route',
        'invalid_hook',
        'invalid_status',
        'route_outside_api',
      ]),
    );
  });

  test('route paths join, list parameters and erase their names', () {
    expect(RoutePaths.join('/tasks/', '/:id/'), '/tasks/:id');
    expect(RoutePaths.parameters('/:org/users/:id/*'), ['org', 'id', '*']);
    expect(RoutePaths.shape('/a/:x/b'), RoutePaths.shape('/a/:y/b'));
  });
}
