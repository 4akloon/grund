import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/construct/generation_result.dart';
import 'package:grund_generator/src/constructs/module_construct.dart';
import 'package:grund_generator/src/constructs/provider_construct.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

const _generator = GrundGenerator([ModuleConstruct(), ProviderConstruct()]);

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  Future<GenerationResult> generate(List<String> paths) async =>
      _generator.generate(await fixture.collect(paths));

  test('one function per module, on the explicit API', () async {
    final result = await generate([
      'lib/modules/basic.dart',
      'lib/modules/app.dart',
    ]);

    expect(result.diagnostics, isEmpty);
    expect(
      result.library,
      contains('''
/// The module of `AppModule`.
grund.Module appModule() => grund.Module(
  id: 'AppModule',
  imports: [dbModule(), i1.explicitModule()],
  exports: [dbModule()],
);

/// The module of `DbModule`.
grund.Module dbModule() => grund.Module(
  id: 'db',
  providers: [
    grund.Provider<i2.Repo>(_createRepo),
    grund.Provider<i2.Clock>(_createSystemClock),
    grund.Provider<String>.value('postgres://localhost', token: i2.dbUrl),
    grund.Provider<i2.AppConfig>.value(i2.appConfig),
  ],
  exports: [i2.Repo, i2.dbUrl],
  global: true,
);
'''),
    );
  });

  test('imports are prefixed in order of first use, grund by name', () async {
    final result = await generate([
      'lib/modules/basic.dart',
      'lib/modules/app.dart',
    ]);

    expect(
      result.library,
      contains('''
import 'package:cases_app/modules/basic.dart' as i2;
import 'package:cases_app/modules/explicit.dart' as i1;
import 'package:grund/grund.dart' as grund;
'''),
    );
  });

  test('ids, import cycles, duplicate providers, exports, constants', () async {
    final result = await generate([
      'lib/modules/structure_errors.dart',
      'lib/modules/basic.dart',
    ]);

    expect(result.library, isNull);
    expect(result.diagnostics.map((d) => '$d'), [
      'lib/modules/structure_errors.dart:16:7: error: Modules FirstModule and '
          'SecondModule share the id "shared". Give each @Module its own id. '
          '[duplicate_module_id]',
      'lib/modules/structure_errors.dart:20:7: error: Module imports form a '
          'cycle: PingModule -> PongModule -> PingModule. Move the shared '
          'providers into a third module imported by both. '
          '[circular_module_import]',
      'lib/modules/structure_errors.dart:32:7: error: Module "SloppyModule" '
          'declares SystemClock more than once. [duplicate_provider]',
      'lib/modules/structure_errors.dart:32:7: error: Module "SloppyModule" '
          'exports Repo, which is neither one of its providers nor one of its '
          'imports. [invalid_export]',
      'lib/modules/structure_errors.dart:32:7: error: Module "SloppyModule" '
          'exports module SecondModule, which is neither one of its providers '
          'nor one of its imports. [invalid_export]',
      'lib/modules/structure_errors.dart:32:7: error: Module "SloppyModule": '
          'the value of _Secret cannot be written in generated code: _Secret '
          'is private. Use public constants and const constructors of public '
          'classes. [unsupported_constant]',
    ]);
  });

  test('every unreadable entry is reported at its module', () async {
    final result = await generate([
      'lib/modules/invalid_entries.dart',
      'lib/modules/basic.dart',
    ]);

    expect(result.diagnostics, hasLength(7));
    expect(result.diagnostics.map((d) => d.code.id).toSet(), {
      'invalid_module_entry',
    });
    expect(
      '${result.diagnostics.first}',
      'lib/modules/invalid_entries.dart:17:7: error: Module "BrokenModule": '
          'controllers: Repo is not a @Controller class of this package. '
          '[invalid_module_entry]',
    );
  });

  test('output is byte-identical across runs and input orders', () async {
    final paths = [
      'lib/modules/basic.dart',
      'lib/modules/app.dart',
      'lib/modules/explicit.dart',
      'lib/modules/with_controller.dart',
    ];

    final first = await generate(paths);
    final again = await generate(paths);
    final reversed = await generate(paths.reversed.toList());
    final rotated = await generate([...paths.skip(2), ...paths.take(2)]);

    expect(first.library, isNotNull);
    expect(again.library, first.library);
    expect(reversed.library, first.library);
    expect(rotated.library, first.library);
  });
}
