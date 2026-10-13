import 'package:dartnest_generator/src/collector/package_collector.dart';
import 'package:dartnest_generator/src/model/body_kind.dart';
import 'package:dartnest_generator/src/model/controller_model.dart';
import 'package:dartnest_generator/src/model/package_model.dart';
import 'package:dartnest_generator/src/model/parameter_binding.dart';
import 'package:dartnest_generator/src/model/route_model.dart';
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
  late ControllerModel edge; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('cases_app');
    final libraries = await fixture.libraries([
      'lib/controllers/edge_handlers.dart',
    ]);
    package = PackageCollector('cases_app', fixture.root).collect(libraries);
    edge = package.controllers.single;
  });

  RouteModel route(String handler) =>
      edge.routes.firstWhere((r) => r.handlerName == handler);

  List<String> bindings(String handler) => [
    for (final p in route(handler).parameters)
      '${p.name}: ${_binding(p.binding)}',
  ];

  test('annotations of one kind add up; a non-class type is invalid', () {
    expect(
      [for (final g in edge.enhancers.guards) '${g.type.name} ${g.isValid}'],
      ['OpenGuard true', 'dynamic false'],
    );
  });

  test('body kinds', () {
    expect(bindings('nullableBody'), ['body: body unsupported']);
    expect(bindings('strings'), ['body: body unsupported']);
    expect(bindings('dynamicMap'), ['body: body jsonObject']);
    expect(bindings('intKeys'), ['body: body unsupported']);
    expect(bindings('bodies'), [
      'staticFrom: body fromJson',
      'instanceFrom: body unsupported',
      'twoArgs: body unsupported',
      'namedArg: body unsupported',
      'wrongParam: body unsupported',
    ]);
    expect(bindings('moreBodies'), [
      'wrongMap: body unsupported',
      'box: body unsupported',
      'function: body unsupported',
    ]);
    expect(
      route('moreBodies').parameters.first.binding,
      isA<BodyBinding>().having((b) => b.kind, 'kind', BodyKind.unsupported),
    );
  });

  test('scalar bindings', () {
    expect(bindings('pathList'), [
      'id: Parameter id (List<int>): @Param supports String, int, double, '
          'num, bool, DateTime and enums, nullable or not.',
    ]);
    expect(bindings('scalars'), [
      'when: path when',
      'ratio: query ratio',
      'id: header x-id',
      'flag: query flag',
      'n: query n',
    ]);
    expect(bindings('sealed'), ['status: query status']);
    final named = route('named').parameters.single;
    expect(named.isNamed, isTrue);
    expect(route('scalars').parameters.first.isNamed, isFalse);
  });

  test('a private handler is a problem', () {
    expect(
      route('_hidden').problem,
      'Handler EdgeController._hidden is private.',
    );
    expect(route('named').problem, isNull);
  });

  test('data classes follow wrappers, fields and self references', () {
    expect(
      [for (final d in package.dtos) d.type.name],
      [
        'InstanceFrom',
        'NamedArg',
        'Node',
        'Sealed',
        'StaticFrom',
        'TwoArgs',
        'WrongMap',
        'WrongParam',
        'CreateUser',
      ],
    );
  });

  test('fields: JsonKey without a name, other annotations, getters', () {
    final node = package.dtos.firstWhere((d) => d.type.name == 'Node');

    expect(
      [for (final f in node.fields) '${f.name}/${f.jsonName}: ${f.type}'],
      ['next/next: Node?', 'label/label: String', 'legacy/legacy: int'],
    );
    expect(node.fields[1].defaultValue, "'n'");
    expect(node.fields.first.defaultValue, isNull);
  });

  test('a class without an unnamed constructor has no defaults', () {
    final sealed = package.dtos.firstWhere((d) => d.type.name == 'Sealed');

    expect(sealed.fields.single.defaultValue, isNull);
    expect(sealed.hasFromJson, isFalse);
    expect(
      package.dtos.firstWhere((d) => d.type.name == 'StaticFrom').hasFromJson,
      isTrue,
    );
  });
}
