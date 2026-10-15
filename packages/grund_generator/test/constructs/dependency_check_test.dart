import 'package:grund_generator/src/constructs/module_construct.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  Future<List<String>> diagnostics(List<String> paths) async {
    final package = await fixture.collect(paths);
    return [
      for (final d
          in const ModuleConstruct().validate(package).toList()..sort())
        '$d',
    ];
  }

  test('missing providers of classes, controllers and components', () async {
    final found = await diagnostics([
      'lib/dependencies/graph.dart',
      'lib/modules/basic.dart',
    ]);

    expect(found.where((d) => d.endsWith('[missing_provider]')), [
      'lib/dependencies/graph.dart:36:15: error: No provider for Clock in '
          'module "MailModule" (resolving: Mailer). It is declared in '
          'module(s) [db]; export it there and import that module into '
          '"MailModule". [missing_provider]',
      'lib/dependencies/graph.dart:36:44: error: No provider for '
          'Token<String>(smtp.url) in module "MailModule" (resolving: '
          'Mailer). [missing_provider]',
      'lib/dependencies/graph.dart:51:13: error: No provider for OpenGuard '
          'in module "MailModule" (resolving: MailController). '
          '[missing_provider]',
      'lib/dependencies/graph.dart:53:36: error: No provider for Engine in '
          'module "MailModule" (resolving: MailController). It is declared in '
          'module(s) [CarModule]; export it there and import that module into '
          '"MailModule". [missing_provider]',
    ]);
  });

  test('a circular dependency is reported once', () async {
    final found = await diagnostics([
      'lib/dependencies/graph.dart',
      'lib/modules/basic.dart',
    ]);

    expect(found.where((d) => d.endsWith('[circular_dependency]')), [
      'lib/dependencies/graph.dart:11:13: error: Circular dependency: Engine '
          '-> Wheel -> Engine. [circular_dependency]',
    ]);
  });

  // Review Focus 4: no false missing_provider next to an opaque module.
  test('a module built by a function turns the check off', () async {
    final found = await diagnostics([
      'lib/dependencies/graph.dart',
      'lib/modules/basic.dart',
      'lib/modules/app.dart',
    ]);

    expect(found, isEmpty);
  });

  test('structural errors come alone, without resolution noise', () async {
    final found = await diagnostics([
      'lib/dependencies/graph.dart',
      'lib/modules/structure_errors.dart',
      'lib/modules/basic.dart',
    ]);

    expect(found, hasLength(6));
    expect(found.where((d) => d.contains('[missing_provider]')), isEmpty);
  });
}
