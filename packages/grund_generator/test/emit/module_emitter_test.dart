import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

const _modules = 'lib/emit/modules.module.g.dart';

void main() {
  late FixturePackage fixture;
  late String source; // Set in setUpAll.

  setUpAll(() async {
    fixture = FixturePackage.open('cases_app');
    final package = await fixture.collect(['lib/emit/modules.dart']);
    final result = const GrundGenerator.core().generate(package);
    expect(result.diagnostics, isEmpty);
    source = result.files[_modules] ?? '';
  });

  test('the output is one file next to its library', () {
    expect(source, startsWith(LibraryWriter.header));
  });

  test('a module becomes a mixin on the core Module', () {
    expect(source, contains(r'mixin $EmitDbModule on grund.Module {'));
    expect(source, contains(r'mixin $EmitAppModule on grund.Module {'));
  });

  test('imports are plain instances in annotation order', () {
    expect(source, contains('List<grund.Module> get imports => ['));
    expect(
      source,
      contains(
        "i1.EmitDbModule(),\n    i1.EmitExplicitModule(name: 'x'),\n  ];",
      ),
    );
  });

  test('a class provider calls its constructor with injected arguments', () {
    expect(source, contains('(i) => i1.Repo('));
    expect(source, contains('i<i1.Clock>(),'));
    expect(source, contains("i<i1.PrimaryDb>('primary'),"));
    expect(source, contains('config: i<i1.AppConfig>(),'));
  });

  test('dependsOn is sorted by key, not by parameter order', () {
    expect(
      source,
      contains(
        'dependsOn: const [\n'
        '        grund.Key<i1.AppConfig>(),\n'
        '        grund.Key<i1.Clock>(),\n'
        "        grund.Key<i1.PrimaryDb>('primary'),\n"
        '      ],',
      ),
    );
  });

  test('Bind registers the implementation under the interface', () {
    expect(
      source,
      contains(
        'grund.Singleton<i1.Clock>((i) => i1.SystemClock(), '
        'dependsOn: const [])',
      ),
    );
  });

  test('scopes map to Singleton, Scoped and Transient', () {
    expect(source, contains('grund.Scoped<i1.Tx>('));
    expect(source, contains('grund.Transient<i1.Counter>('));
    expect(source, contains('grund.Singleton<i1.Repo>('));
  });

  test('a @Provides method is called on its module class', () {
    expect(source, contains('(i) => i1.EmitDbModule.config()'));
    expect(
      source,
      contains(
        "i1.EmitDbModule.session(i<i1.Clock>(), i<i1.PrimaryDb>('primary'))",
      ),
    );
  });

  test('an async @Provides is a plain Singleton of the awaited type', () {
    expect(source, contains("grund.Singleton<i1.Session>("));
    expect(source, isNot(contains('Singleton.factory')));
    expect(source, contains("name: 'main'"));
  });

  test('a call-scoped @Provides is Scoped', () {
    expect(source, contains('grund.Scoped<i1.Handle>('));
  });

  test('a name is escaped in every position', () {
    expect(source, contains(r"name: 'a\'b\$c'"));
  });

  test('exports are const keys in order, then re-exported modules', () {
    expect(
      source,
      contains(
        'List<Object> get exports => const [\n'
        '    grund.Key<i1.Clock>(),\n'
        "    grund.Key<i1.PrimaryDb>('primary'),\n"
        '    grund.Key<i1.Repo>(),\n'
        "    grund.Key<i1.Session>('main'),\n"
        '  ];',
      ),
    );
    expect(source, contains('exports => [i1.EmitDbModule()];'));
  });

  test('global is overridden only by a global module', () {
    expect('bool get global => true'.allMatches(source), hasLength(1));
  });

  test('two generations give the same bytes', () async {
    final package = await fixture.collect(['lib/emit/modules.dart']);

    final again = const GrundGenerator.core().generate(package).files[_modules];

    expect(again, source);
  });
}
