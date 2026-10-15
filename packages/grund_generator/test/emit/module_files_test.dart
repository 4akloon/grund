import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late FixturePackage fixture;

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  Future<GenerationResult> generate(List<String> libraries) async =>
      const GrundGenerator.core().generate(await fixture.collect(libraries));

  test('every library with a module gets a file of its own', () async {
    final result = await generate([
      'lib/emit/modules.dart',
      'lib/emit/second.dart',
    ]);

    expect(result.diagnostics, isEmpty);
    expect(result.files.keys, [
      'lib/emit/modules_module.g.dart',
      'lib/emit/second_module.g.dart',
    ]);
    expect(
      result.files['lib/emit/second_module.g.dart'],
      allOf(
        contains(r'mixin $EmitMailModule'),
        isNot(contains('EmitDbModule')),
      ),
    );
  });

  test('a library without a module has no output', () async {
    final result = await generate(['lib/emit/plain.dart']);

    expect(result.diagnostics, isEmpty);
    expect(result.files, isEmpty);
  });

  test('import prefixes are numbered within each file', () async {
    final result = await generate([
      'lib/emit/modules.dart',
      'lib/emit/second.dart',
    ]);
    final second = result.files['lib/emit/second_module.g.dart']!;

    expect(
      second,
      contains("import 'package:cases_app/emit/second.dart' as i1;"),
    );
    expect(second, isNot(contains(' as i2;')));
  });

  test('private classes a module names are reported', () async {
    final result = await generate(['lib/emit/private_types.dart']);

    expect(
      {for (final d in result.diagnostics) d.code.id},
      {'invalid_constructor', 'private_declaration'},
    );
    expect(
      result.diagnostics.map((d) => d.toString()).join('\n'),
      allOf(
        contains('_Hidden'),
        contains('_Secret'),
        contains('lib/emit/private_types_module.g.dart'),
      ),
    );
    expect(result.files, isEmpty);
  });

  test('a private provider class is reported once', () async {
    final result = await generate(['lib/emit/private_types.dart']);
    final hidden = [
      for (final d in result.diagnostics)
        if (d.location.line == 10) d.code.id,
    ];

    expect(hidden, ['invalid_constructor']);
  });

  test('output of an earlier run is not collected', () async {
    final package = await fixture.collect([
      'lib/emit/second.dart',
      'lib/emit/stale_module.g.dart',
    ]);

    expect([for (final m in package.modules) m.type.name], ['EmitMailModule']);
  });

  test('a hand-written file named like an output is still collected', () async {
    final package = await fixture.collect([
      'lib/emit/second.dart',
      'lib/emit/handwritten_module.g.dart',
    ]);

    expect(
      [for (final m in package.modules) m.type.name],
      ['HandwrittenModule', 'EmitMailModule'],
    );
  });
}
