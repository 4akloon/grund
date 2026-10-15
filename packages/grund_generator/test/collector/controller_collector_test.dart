import 'package:grund_generator/src/collector/package_collector.dart';
import 'package:grund_generator/src/model/body_kind.dart';
import 'package:grund_generator/src/model/constant_value.dart';
import 'package:grund_generator/src/model/controller_model.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:grund_generator/src/model/parameter_binding.dart';
import 'package:grund_generator/src/model/route_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

String _binding(ParameterBinding binding) => switch (binding) {
  PathBinding(:final name) => 'path $name',
  QueryBinding(:final name) => 'query $name',
  HeaderBinding(:final name) => 'header $name',
  BodyBinding(:final kind) => 'body ${kind.name}',
  ContextBinding() => 'context',
  RequestBinding() => 'request',
  InvalidBinding(:final problem) => problem,
};

void main() {
  late PackageModel package; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('cases_app');
    final libraries = await fixture.libraries([
      'lib/controllers/users.dart',
      'lib/controllers/invalid_handlers.dart',
    ]);
    package = PackageCollector('cases_app', fixture.root).collect(libraries);
  });

  ControllerModel controller(String name) =>
      package.controllers.firstWhere((c) => c.type.name == name);

  RouteModel route(String controllerName, String handler) => controller(
    controllerName,
  ).routes.firstWhere((r) => r.handlerName == handler);

  List<String> bindings(String controllerName, String handler) => [
    for (final p in route(controllerName, handler).parameters)
      '${p.name}: ${_binding(p.binding)}',
  ];

  test('a controller keeps its path, enhancers and metadata', () {
    final users = controller('UsersController');

    expect(users.path, '/users');
    expect(users.documentation, '/// Users.');
    expect(
      [for (final g in users.enhancers.guards) g.type.name],
      ['OpenGuard'],
    );
    final roles = users.metadata.single as ObjectConstant;
    expect(roles.type.name, 'Roles');
    expect(users.constructor.dependencies, isEmpty);
  });

  test('routes in declaration order, without plain methods', () {
    expect(
      [
        for (final r in controller('UsersController').routes)
          '${r.method} ${r.path} ${r.handlerName}',
      ],
      [
        'GET  list',
        'GET /:id find',
        'POST  create',
        'PUT /:id/note note',
        'PUT /:id/avatar avatar',
        'PATCH /:id merge',
        'DELETE  clear',
      ],
    );
    expect(
      route('UsersController', 'list').returnType.display,
      'Future<List<User>>',
    );
  });

  test('route enhancers and metadata', () {
    final create = route('UsersController', 'create');

    expect(create.enhancers.pipes.single.type.name, 'TrimPipe');
    expect(create.enhancers.filters.single.isValid, isTrue);
    expect(create.metadata.single, isA<ObjectConstant>());
    expect(
      route('UsersController', 'list').enhancers.interceptors.single.isValid,
      isTrue,
    );
    expect(create.problem, isNull);
  });

  test('parameters bind to path, query, header, body, context, request', () {
    expect(bindings('UsersController', 'list'), [
      'limit: query limit',
      'status: query status',
    ]);
    expect(bindings('UsersController', 'find'), [
      'id: path id',
      'trace: header x-trace',
    ]);
    expect(bindings('UsersController', 'create'), [
      'body: body fromJson',
      'context: context',
    ]);
    expect(bindings('UsersController', 'note'), [
      'id: path id',
      'text: body text',
      'request: request',
    ]);
    expect(bindings('UsersController', 'avatar').last, 'bytes: body bytes');
    expect(bindings('UsersController', 'merge'), ['patch: body jsonObject']);
  });

  test('parameters the generator cannot bind', () {
    expect(bindings('BrokenController', 'unbound'), [
      'value: Parameter value (int) needs @Param, @Query, @Header or @Body, '
          'or the type ExecutionContext or HttpRequest.',
    ]);
    expect(bindings('BrokenController', 'twice'), [
      'id: Parameter id (int) has more than one of @Param, @Query, @Header '
          'and @Body.',
    ]);
    expect(bindings('BrokenController', 'list'), [
      'tags: Parameter tags (List<String>): @Query supports String, int, '
          'double, num, bool, DateTime and enums, nullable or not.',
    ]);
    expect(bindings('BrokenController', 'header'), [
      'count: Parameter count (int): a @Header parameter is String or '
          'String?.',
    ]);
    expect(
      route('BrokenController', 'body').parameters.single.binding,
      isA<BodyBinding>().having((b) => b.kind, 'kind', BodyKind.unsupported),
    );
  });

  test('handlers that cannot be routes', () {
    expect(
      route('BrokenController', 'twoRoutes').problem,
      'Handler BrokenController.twoRoutes has more than one route annotation.',
    );
    expect(
      route('BrokenController', 'notInstance').problem,
      'Handler BrokenController.notInstance is static.',
    );
    expect(
      route('BrokenController', 'generic').problem,
      'Handler BrokenController.generic is generic.',
    );
  });

  test('components of the wrong kind are invalid', () {
    final guards = controller('BrokenController').enhancers.guards;

    expect(
      [for (final g in guards) '${g.type.name} ${g.isValid}'],
      ['PassInterceptor false', 'String false'],
    );
  });

  test('data classes of bodies and results', () {
    expect(
      [for (final d in package.dtos) d.type.name],
      ['Opaque', 'CreateUser', 'User'],
    );
    final user = package.dtos.last;
    expect(user.hasFromJson, isFalse);
    expect(
      [for (final f in user.fields) '${f.name}/${f.jsonName}: ${f.type}'],
      ['id/id: int', 'name/display_name: String', 'status/status: Status'],
    );
    expect(user.fields.last.defaultValue, 'Status.active');
    expect(package.dtos[1].hasFromJson, isTrue);
  });
}
