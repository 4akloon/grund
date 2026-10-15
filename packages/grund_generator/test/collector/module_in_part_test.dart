import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/diagnostic/diagnostic_code.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  test('a module in a part is reported and generates nothing', () async {
    final package = await FixturePackage.open(
      'cases_app',
    ).collect(['lib/uris/part_host.dart']);

    final result = const GrundGenerator.core().generate(package);

    expect([for (final m in package.modules) m.type.name], ['HostModule']);
    final problem = package.modulesInParts.single;
    expect(problem.element, 'PartModule');
    expect(problem.location.path, 'lib/uris/part_host_module.dart');
    expect(result.isSuccess, isFalse);
    expect(result.diagnostics.single.code, DiagnosticCode.moduleInPart);
    expect(result.files.keys, isEmpty);
  });
}
