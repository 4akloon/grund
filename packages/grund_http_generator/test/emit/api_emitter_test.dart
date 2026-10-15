import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late GenerationResult result; // Set in setUpAll.
  late String source; // The part of lib/apis/tasks.dart.

  setUpAll(() async {
    final package = await FixturePackage.open(
      'http_cases_app',
    ).collect(['lib/modules/with_api.dart', 'lib/apis/tasks.dart']);
    result = const GrundGenerator(FixturePackage.constructs).generate(package);
    source = result.files['lib/apis/tasks_api.g.dart'] ?? '';
  });

  test('the package generates without diagnostics', () {
    expect(result.diagnostics, isEmpty);
    expect(result.files.keys, [
      'lib/apis/tasks_api.g.dart',
      'lib/modules/with_api_module.g.dart',
    ]);
  });

  test('an API becomes a final HttpApi part of its library', () {
    expect(source, startsWith(LibraryWriter.header));
    expect(source, contains("part of 'tasks.dart';"));
    expect(source, isNot(contains('import ')));
    expect(source, contains('final class TasksApiRoutes extends http.HttpApi'));
    expect(source, contains('TasksApiRoutes(super.injector, this._api);'));
    expect(source, contains('final TasksApi _api;'));
  });

  test('path and hooks of the API are overridden with prefixed names', () {
    expect(source, contains("String get path => '/tasks';"));
    expect(
      source,
      contains(
        'List<http.HookRef<http.HttpHook>> get use => const [\n'
        '    http.HookRef<ApiKeyHook>.type(),\n'
        '  ];',
      ),
    );
  });

  test('path, query, header and cookie parameters use their reader', () {
    expect(source, contains("c.path.integer('id')"));
    expect(source, contains("c.query.booleanOrNull('done')"));
    expect(source, contains("c.headers.stringOrNull('x-trace')"));
    expect(source, contains("c.cookies.string('session')"));
    expect(source, contains("c.query.dateTime('since')"));
    expect(source, contains("c.query.uriOrNull('next')"));
  });

  test('a repeated query parameter is read with all', () {
    expect(source, contains("c.query.all('tag')"));
  });

  test('an enum parameter passes the values of the enum', () {
    expect(source, contains("c.path.enumOf('priority', Priority.values)"));
  });

  test('a default turns the reader nullable and falls back to it', () {
    expect(
      source,
      contains(
        "pageSize: c.query.integerOrNull('page_size', min: 1, max: 100) ?? 20",
      ),
    );
  });

  test('validators become reader arguments, escaped', () {
    expect(source, contains('minLength: 1'));
    expect(source, contains('maxLength: 8'));
    expect(source, contains(r"pattern: '^\\w+\$'"));
  });

  test('a body is read with the fromJson of its type', () {
    expect(source, contains('await c.body(CreateTask.fromJson)'));
    expect(source, contains('await c.bodyList(CreateTask.fromJson)'));
    expect(source, contains('await c.body((json) => json)'));
    expect(source, contains('await c.bytes()'));
  });

  test('a lambda is async only when it awaits', () {
    expect(RegExp(r'\(c\) async =>\s+_api\.create\(').hasMatch(source), isTrue);
    expect(source, contains("(c) => _api.find(c.path.integer('id'))"));
  });

  test('the context and call-scope values are passed through', () {
    expect(source, contains('c<CurrentUser>()'));
    expect(RegExp(r'_api\.mark\(\s*c\.path\.integer').hasMatch(source), isTrue);
  });

  test('status and hooks of a route are named arguments', () {
    expect(source, contains('status: 201,'));
    expect(
      source,
      contains('http.HookRef<RolesHook>.instance(RolesHook(Priority.high))'),
    );
  });

  test('a void result is answered with null after the call', () {
    expect(source, contains('await _api.remove('));
    expect(source, contains('return null;'));
    expect(source, contains('_api.mark('));
  });

  test('a byte stream is returned as is', () {
    expect(source, contains('(c) => _api.export('));
  });

  test('every route is a prefixed Route constructor', () {
    expect(source, contains('http.Route.get('));
    expect(source, contains('http.Route.post('));
    expect(source, contains('http.Route.put('));
    expect(source, contains('http.Route.delete('));
  });
}
