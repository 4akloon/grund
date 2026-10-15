import 'package:grund_generator/src/model/api_model.dart';
import 'package:grund_generator/src/model/body_kind.dart';
import 'package:grund_generator/src/model/http_package_model.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:grund_generator/src/model/param_model.dart';
import 'package:grund_generator/src/model/param_source.dart';
import 'package:grund_generator/src/model/return_kind.dart';
import 'package:grund_generator/src/model/route_model.dart';
import 'package:grund_generator/src/model/validator_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    package = await FixturePackage.open(
      'cases_app',
    ).collect(['lib/apis/tasks.dart', 'lib/apis/invalid.dart']);
  });

  ApiModel api(String name) => package
      .extensionModel<HttpPackageModel>()!
      .apis
      .firstWhere((a) => a.type.name == name);

  RouteModel route(String api_, String name) =>
      api(api_).routes.firstWhere((r) => r.handlerName == name);

  ParamModel param(String api_, String route_, String name) =>
      route(api_, route_).parameters.firstWhere((p) => p.name == name);

  String source(ParamModel param) => switch (param.source) {
    ValueSource(:final location, :final name, :final kind) =>
      '${location.name} $name ${kind.name}',
    BodySource(:final kind) => 'body ${kind.name}',
    ContextSource() => 'context',
    CallScopeSource(:final key) => 'call scope $key',
    InvalidSource(:final problem) => 'invalid: $problem',
  };

  test('an api keeps its path, hooks and routes in source order', () {
    final tasks = api('TasksApi');

    expect(tasks.path, '/tasks');
    expect(tasks.use.single.type.display, 'ApiKeyHook');
    expect(tasks.use.single.isInstance, isFalse);
    expect(
      [for (final r in tasks.routes) '${r.method} ${r.path}'],
      [
        'GET /:id',
        'GET /',
        'POST /',
        'DELETE /:id',
        'PUT /:id/priority/:priority',
        'PUT /:id/raw',
        'POST /import',
        'POST /free',
        'GET /export',
      ],
    );
  });

  test('a route keeps status and hook instances', () {
    final create = route('TasksApi', 'create');

    expect(create.status, 201);
    expect(create.use.single.type.display, 'RolesHook');
    expect(create.use.single.isInstance, isTrue);
  });

  test('return types classify into value, none and byte stream', () {
    expect(route('TasksApi', 'find').returnKind, ReturnKind.value);
    expect(route('TasksApi', 'remove').returnKind, ReturnKind.none);
    expect(route('TasksApi', 'mark').returnKind, ReturnKind.none);
    expect(route('TasksApi', 'export').returnKind, ReturnKind.byteStream);
    expect(route('BadApi', 'events').returnKind, ReturnKind.stream);
    expect(route('BadApi', 'callback').returnKind, ReturnKind.unsupported);
  });

  test('parameters read their source, name and value kind', () {
    expect(source(param('TasksApi', 'find', 'id')), 'path id integer');
    expect(source(param('TasksApi', 'list', 'tag')), 'query tag stringList');
    expect(
      source(param('TasksApi', 'list', 'pageSize')),
      'query page_size integer',
    );
    expect(
      source(param('TasksApi', 'remove', 'trace')),
      'header x-trace string',
    );
    expect(
      source(param('TasksApi', 'raw', 'session')),
      'cookie session string',
    );
    expect(
      source(param('TasksApi', 'mark', 'priority')),
      'path priority enumeration',
    );
    expect(
      source(param('TasksApi', 'export', 'since')),
      'query since dateTime',
    );
  });

  test('bodies are objects, lists, JSON objects or bytes', () {
    BodyKind kind(String route_, String name) =>
        (param('TasksApi', route_, name).source as BodySource).kind;

    expect(kind('create', 'dto'), BodyKind.object);
    expect(kind('import', 'tasks'), BodyKind.list);
    expect(kind('free', 'json'), BodyKind.jsonObject);
    expect(kind('raw', 'data'), BodyKind.bytes);
  });

  test('unannotated parameters are the context or a call scope value', () {
    expect(source(param('TasksApi', 'mark', 'ctx')), 'context');
    expect(
      source(param('TasksApi', 'create', 'user')),
      'call scope CurrentUser',
    );
  });

  test('named parameters and defaults are kept', () {
    final pageSize = param('TasksApi', 'list', 'pageSize');

    expect(pageSize.isNamed, isTrue);
    expect(pageSize.defaultValue, isNotNull);
    expect(param('TasksApi', 'list', 'done').type.display, 'bool?');
    expect(param('TasksApi', 'list', 'done').defaultValue, isNull);
  });

  test('validators are read with their arguments', () {
    final range = param('TasksApi', 'list', 'pageSize').validators.single;
    final [length, pattern] = param('TasksApi', 'list', 'q').validators;

    expect((range as RangeValidator).min, 1);
    expect(range.max, 100);
    expect((length as LengthValidator).max, 8);
    expect((pattern as PatternValidator).regex, r'^\w+$');
  });

  test('problems of a route are kept for the checks', () {
    expect(route('BadApi', 'twice').problem, contains('more than one route'));
    expect(route('BadApi', 'staticHandler').problem, contains('is static'));
    expect(source(param('BadApi', 'noSource', 'page')), contains('no source'));
    expect(source(param('BadApi', 'both', 'x')), contains('more than one of'));
    expect(source(param('BadApi', 'number', 'n')), contains('supports'));
    expect(
      source(param('BadApi', 'body', 'dto')),
      'body ${BodyKind.unsupported.name}',
    );
    expect(route('BadApi', 'hook').invalidEntries, hasLength(1));
    expect(route('BadApi', 'hook').status, 700);
    expect(api('BadApi').invalidEntries, hasLength(1));
  });

  test('routes outside an api are collected apart', () {
    expect(
      [
        for (final r in package.extensionModel<HttpPackageModel>()!.strayRoutes)
          r.handlerName,
      ],
      ['stray'],
    );
  });
}
