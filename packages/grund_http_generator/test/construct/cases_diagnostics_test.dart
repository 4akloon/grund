import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

/// The diagnostics of the invalid libraries of `http_cases_app`, with their
/// exact position: a user finds the problem by `path:line:col`.
void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('http_cases_app'));

  Future<List<String>> problems(List<String> paths) async {
    final package = await fixture.collect(paths);
    return [
      for (final d in const GrundGenerator(
        FixturePackage.constructs,
      ).generate(package).diagnostics)
        '${d.location} ${d.code.id}',
    ];
  }

  test(
    'every invalid route of apis/invalid.dart is found where it is',
    () async {
      expect(await problems(['lib/apis/tasks.dart', 'lib/apis/invalid.dart']), [
        'lib/apis/invalid.dart:11:13 invalid_hook',
        'lib/apis/invalid.dart:11:13 missing_part_directive',
        'lib/apis/invalid.dart:11:13 missing_required_import',
        'lib/apis/invalid.dart:15:8 invalid_route_handler',
        'lib/apis/invalid.dart:19:15 invalid_route_handler',
        'lib/apis/invalid.dart:23:16 stream_return_reserved',
        'lib/apis/invalid.dart:27:21 parameter_without_source',
        'lib/apis/invalid.dart:31:28 missing_from_json',
        'lib/apis/invalid.dart:35:32 unknown_path_parameter',
        'lib/apis/invalid.dart:39:34 invalid_handler_parameter',
        'lib/apis/invalid.dart:43:45 invalid_validator',
        'lib/apis/invalid.dart:47:28 invalid_handler_parameter',
        'lib/apis/invalid.dart:51:19 unsupported_return_type',
        'lib/apis/invalid.dart:59:8 duplicate_route',
        'lib/apis/invalid.dart:63:8 invalid_hook',
        'lib/apis/invalid.dart:63:8 invalid_status',
        'lib/apis/invalid.dart:74:8 route_outside_api',
      ]);
    },
  );

  test(
    'a host without its part or import is reported on its first api',
    () async {
      expect(await problems(['lib/apis/no_part.dart']), [
        'lib/apis/no_part.dart:7:13 missing_part_directive',
      ]);
      expect(await problems(['lib/apis/unhosted.dart']), [
        'lib/apis/unhosted.dart:8:13 missing_part_directive',
        'lib/apis/unhosted.dart:8:13 missing_required_import',
      ]);
    },
  );

  test(
    'the valid libraries of http_cases_app generate without a diagnostic',
    () async {
      expect(
        await problems(['lib/modules/with_api.dart', 'lib/apis/tasks.dart']),
        isEmpty,
      );
    },
  );
}
