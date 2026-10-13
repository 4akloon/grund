import 'package:dartnest_generator/src/construct/dartnest_generator.dart';
import 'package:dartnest_generator/src/constructs/controller_check.dart';
import 'package:dartnest_generator/src/constructs/controller_construct.dart';
import 'package:dartnest_generator/src/model/body_kind.dart';
import 'package:dartnest_generator/src/model/component_reference.dart';
import 'package:dartnest_generator/src/model/constant_value.dart';
import 'package:dartnest_generator/src/model/constructor_model.dart';
import 'package:dartnest_generator/src/model/controller_model.dart';
import 'package:dartnest_generator/src/model/enhancers_model.dart';
import 'package:dartnest_generator/src/model/parameter_binding.dart';
import 'package:dartnest_generator/src/model/provider_key.dart';
import 'package:dartnest_generator/src/model/route_model.dart';
import 'package:dartnest_generator/src/model/type_kind.dart';
import 'package:dartnest_generator/src/model/type_model.dart';
import 'package:dartnest_generator/src/model/dependency_model.dart';
import 'package:test/test.dart';

import '../helpers/controller_models.dart';

const _generator = DartnestGenerator([ControllerConstruct()]);

final _string = ControllerModels.core('String');
final _int = ControllerModels.core('int');

String _library(List<Object> controllers) {
  final result = _generator.generate(
    ControllerModels.package([...controllers.cast()]),
  );
  expect(result.diagnostics, isEmpty);
  return result.library!
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r',\s?\)'), ')');
}

List<String> _problems(List<Object> controllers) => [
  for (final d
      in _generator
          .generate(ControllerModels.package([...controllers.cast()]))
          .diagnostics)
    '${d.code.id}: ${d.message}',
];

/// A controller with dependencies, all four component lists and a request
/// and a context parameter.
ControllerModel _richController() => ControllerModels.controller(
  'Rich',
  '/r',
  [
    ControllerModels.route(
      'GET',
      '',
      parameters: [
        ControllerModels.parameter(
          'r',
          ControllerModels.type('HttpRequest'),
          const RequestBinding(),
        ),
        ControllerModels.parameter(
          'x',
          ControllerModels.type('ExecutionContext'),
          const ContextBinding(),
        ),
      ],
    ),
  ],
  constructor: ConstructorModel([
    ControllerModels.dependency('Repo'),
    ControllerModels.dependency('Clock', isNamed: true),
  ]),
  enhancers: EnhancersModel(
    guards: [ControllerModels.component('G')],
    interceptors: [ControllerModels.component('I')],
    pipes: [ControllerModels.component('P')],
    filters: [ControllerModels.component('F')],
  ),
);

/// A constructor dependency on a token whose expression is [unsupported].
DependencyModel _unsupportedToken(UnsupportedConstant unsupported) {
  return DependencyModel.injected(
    name: 'url',
    isNamed: false,
    location: ControllerModels.location,
    key: TokenKey(
      valueType: _string,
      name: 'db.url',
      expression: ObjectConstant(
        type: TypeModel(name: 'Value', kind: TypeKind.interface),
        constructorName: '',
        positional: [unsupported],
      ),
    ),
  );
}

/// Routes whose `@Param('id')` is not in their path.
List<RouteModel> _unknownPathRoutes() => [
  for (final (name, path) in [('none', '/r'), ('wild', '/s/*')])
    ControllerModels.route(
      'GET',
      path,
      name: name,
      parameters: [
        ControllerModels.parameter('p', _int, const PathBinding('id')),
      ],
    ),
];

/// A controller whose handlers, constructor and metadata are all unusable.
ControllerModel _badController(UnsupportedConstant unsupported) =>
    ControllerModels.controller(
      'Bad',
      '/b',
      [
        ControllerModels.route(
          'GET',
          '/p',
          name: '_hidden',
          problem: 'Handler Bad._hidden is private.',
        ),
        ControllerModels.route(
          'GET',
          '/q',
          name: 'tagged',
          metadata: [unsupported],
          enhancers: const EnhancersModel(
            pipes: [
              ComponentReference(
                TypeModel(name: 'Q', kind: TypeKind.interface),
                isValid: false,
              ),
            ],
          ),
        ),
        ..._unknownPathRoutes(),
      ],
      constructor: const ConstructorModel.invalid('Bad is private.'),
      metadata: [unsupported],
    );

void main() {
  test('void handlers return null, Future<void> handlers await', () {
    final library = _library([
      ControllerModels.controller('Tasks', '', [
        ControllerModels.route('DELETE', '/a', name: 'sync'),
        ControllerModels.route(
          'POST',
          '/b',
          name: 'later',
          returnType: TypeModel(
            name: 'Future',
            kind: TypeKind.interface,
            libraryUri: 'dart:async',
            typeArguments: [TypeModel.voidType],
          ),
        ),
        ControllerModels.route('GET', '/c', name: 'plain', returnType: _int),
      ]),
    ]);

    expect(library, contains('(c, _) { c.sync(); return null; }'));
    expect(library, contains('(c, _) async { await c.later(); return null; }'));
    expect(library, contains("(c, _) => c.plain()"));
    expect(library, isNot(contains('path:')));
  });

  test('every binding kind, with its own expression', () {
    final library = _library([
      ControllerModels.controller('Mix', '/m', [
        ControllerModels.route(
          'PUT',
          '/:id',
          name: 'all',
          parameters: [
            ControllerModels.parameter(
              'a',
              _string,
              const HeaderBinding('x-a'),
            ),
            ControllerModels.parameter(
              'b',
              ControllerModels.core('String', isNullable: true),
              const HeaderBinding('x-b'),
            ),
            ControllerModels.body(BodyKind.jsonObject, _string),
            ControllerModels.body(BodyKind.bytes, _string),
            ControllerModels.parameter(
              'n',
              _int,
              const QueryBinding('n'),
              isNamed: true,
            ),
          ],
        ),
      ]),
    ]);

    expect(
      library,
      contains(
        "ctx.header('x-a') ?? (throw const dartnest.BadRequestException(",
      ),
    );
    expect(library, contains('Missing header "x-a".'));
    expect(library, contains("ctx.header('x-b')"));
    expect(library, contains('await ctx.bodyAs<String>((json) => json)'));
    expect(library, contains('await ctx.body.bytes()'));
    expect(library, contains("n: await ctx.query<int>('n')"));
  });

  test('strings from sources are escaped at every site', () {
    final library = _library([
      ControllerModels.controller(r'Odd', r"/a'$b", [
        ControllerModels.route(
          'GET',
          r"/c\d$e",
          parameters: [
            ControllerModels.parameter(
              'h',
              _string,
              const HeaderBinding(r'x-$"y'),
            ),
            ControllerModels.parameter('q', _int, const QueryBinding(r"q'1")),
          ],
          metadata: [const StringConstant(r"m'$")],
        ),
      ]),
    ]);

    expect(library, contains(r"path: '/a\'\$b'"));
    expect(library, contains(r"'/c\\d\$e'"));
    expect(library, contains(r'''ctx.header('x-\$"y')'''));
    expect(library, contains(r"ctx.query<int>('q\'1')"));
    expect(library, contains(r"'m\'\$'"));
  });

  test('dependencies, all four lists and the request binding', () {
    final library = _library([_richController()]);

    expect(
      library,
      contains(
        'create: (i) => i1.Rich(i.get<i1.Repo>(), '
        'clock: i.get<i1.Clock>())',
      ),
    );
    for (final name in [
      'guards: [dartnest.Use<i1.G>()]',
      'interceptors: [dartnest.Use<i1.I>()]',
      'pipes: [dartnest.Use<i1.P>()]',
      'filters: [dartnest.Use<i1.F>()]',
    ]) {
      expect(library, contains(name));
    }
    expect(library, contains('ctx.switchToHttp().request'));
    expect(
      library,
      contains(
        '(c, ctx) { c.handle(ctx.switchToHttp().request, ctx); return null; }',
      ),
    );
  });

  test('metadata, constructors, tokens and handlers it cannot generate', () {
    const unsupported = UnsupportedConstant('_Role is private');
    final problems = _problems([
      _badController(unsupported),
      ControllerModels.controller(
        'Tokens',
        '',
        const [],
        constructor: ConstructorModel([_unsupportedToken(unsupported)]),
      ),
    ]);

    expect(problems, [
      'invalid_component: Q in @UsePipes of Bad.tagged is not a Pipe.',
      'invalid_constructor: Bad is private.',
      'invalid_route_handler: Handler Bad._hidden is private.',
      "unknown_path_parameter: @Param('id') of Bad.none is not in the route "
          'path; it declares no parameters.',
      "unknown_path_parameter: @Param('id') of Bad.wild is not in the route "
          'path; it declares *.',
      'unsupported_constant: Metadata of Bad cannot be written in generated '
          'code: _Role is private. Use public constants and const '
          'constructors of public classes.',
      'unsupported_constant: Metadata of Bad.tagged cannot be written in '
          'generated code: _Role is private. Use public constants and const '
          'constructors of public classes.',
      'unsupported_constant: The token of parameter url of Tokens cannot be '
          'written in generated code: _Role is private. Use a public '
          'constant token.',
    ]);
  });

  test('a body without fromJson and an invalid binding are reported', () {
    final problems = _problems([
      ControllerModels.controller('Raw', '', [
        ControllerModels.route(
          'POST',
          '/a',
          parameters: [
            ControllerModels.body(
              BodyKind.unsupported,
              ControllerModels.type('Opaque'),
            ),
            ControllerModels.parameter(
              'v',
              _int,
              const InvalidBinding('Parameter v (int) must bind.'),
            ),
          ],
        ),
      ]),
    ]);

    expect(problems, [
      'invalid_handler_parameter: Raw.handle: Parameter v (int) must bind.',
      'missing_from_json: @Body parameter body of Raw.handle has type Opaque; '
          '@Body needs a class with a fromJson(Map<String, Object?>) '
          'constructor or static method, Map<String, Object?>, String or '
          'List<int>.',
    ]);
  });

  test('duplicate routes compare the whole path, per method', () {
    final problems = _problems([
      ControllerModels.controller('A', '/x/', [
        ControllerModels.route('GET', '/:id', name: 'one'),
        ControllerModels.route('POST', '/:id', name: 'post'),
      ]),
      ControllerModels.controller('B', '/x', [
        ControllerModels.route('GET', '/:name', name: 'two'),
        ControllerModels.route('GET', '/:name/y', name: 'other'),
      ]),
    ]);

    expect(problems, [
      'duplicate_route: Route GET /x/:name is declared twice: by A.one and '
          'by B.two. Parameter names do not distinguish routes.',
    ]);
    expect(
      ControllerCheck.fullPath(
        ControllerModels.controller('A', '/x/', const []),
        ControllerModels.route('GET', '/:id'),
      ).path,
      '/x/:id',
    );
  });
}
