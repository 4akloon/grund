import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/constructs/controller_construct.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

const _generator = GrundGenerator([ControllerConstruct()]);

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  test('one function per controller, every binding on the context', () async {
    final result = _generator.generate(
      await fixture.collect(['lib/controllers/users.dart']),
    );

    expect(result.diagnostics, isEmpty);
    expect(
      result.library,
      contains(r'''
/// The controller of `UsersController`.
grund.Controller<i1.UsersController> usersController() =>
    grund.Controller<i1.UsersController>(
      path: '/users',
      create: (_) => i1.UsersController(),
      enhancers: const grund.Enhancers(guards: [grund.Use<i2.OpenGuard>()]),
      metadata: const [
        i2.Roles(<String>['admin']),
      ],
      routes: [
        grund.Route.get(
          '',
          (c, ctx) async => c.list(
            await ctx.query<int?>('limit'),
            await ctx.query<i1.Status?>(
              'status',
              pipes: const [grund.EnumPipe(i1.Status.values)],
            ),
          ),
          name: 'list',
          enhancers: const grund.Enhancers(
            interceptors: [grund.Use<i2.PassInterceptor>()],
          ),
        ),
        grund.Route.get(
          '/:id',
          (c, ctx) async =>
              c.find(await ctx.param<int>('id'), ctx.header('x-trace')),
          name: 'find',
        ),
        grund.Route.post(
          '',
          (c, ctx) async =>
              c.create(await ctx.bodyAs(i1.CreateUser.fromJson), ctx),
          name: 'create',
          enhancers: const grund.Enhancers(
            pipes: [grund.Use<i2.TrimPipe>()],
            filters: [grund.Use<i2.StateFilter>()],
          ),
          metadata: const [
            i2.Roles(<String>['owner']),
          ],
        ),
        grund.Route.put('/:id/note', (c, ctx) async {
          c.note(
            await ctx.param<String>('id'),
            await ctx.body.text(),
            ctx.switchToHttp().request,
          );
'''),
    );
  });

  // Review Focus 5: /j/:a and /j/:b are one route.
  test('handlers, parameters, components and routes it rejects', () async {
    final result = _generator.generate(
      await fixture.collect([
        'lib/controllers/invalid_handlers.dart',
        'lib/controllers/users.dart',
      ]),
    );

    expect(result.diagnostics.map((d) => '$d'), [
      'lib/controllers/invalid_handlers.dart:15:13: error: '
          'PassInterceptor in @UseGuards of BrokenController is not a '
          'Guard. [invalid_component]',
      'lib/controllers/invalid_handlers.dart:15:13: error: String in '
          '@UseGuards of BrokenController is not a Guard. '
          '[invalid_component]',
      'lib/controllers/invalid_handlers.dart:18:19: error: '
          'BrokenController.unbound: Parameter value (int) needs @Param, '
          '@Query, @Header or @Body, or the type ExecutionContext or '
          'HttpRequest. [invalid_handler_parameter]',
      'lib/controllers/invalid_handlers.dart:22:43: error: '
          'BrokenController.twice: Parameter id (int) has more than one '
          'of @Param, @Query, @Header and @Body. '
          '[invalid_handler_parameter]',
      'lib/controllers/invalid_handlers.dart:26:40: error: '
          'BrokenController.list: Parameter tags (List<String>): @Query '
          'supports String, int, double, num, bool, DateTime and enums, '
          'nullable or not. [invalid_handler_parameter]',
      'lib/controllers/invalid_handlers.dart:30:37: error: '
          'BrokenController.header: Parameter count (int): a @Header '
          'parameter is String or String?. [invalid_handler_parameter]',
      'lib/controllers/invalid_handlers.dart:34:27: error: @Body '
          'parameter opaque of BrokenController.body has type Opaque; '
          '@Body needs a class with a fromJson(Map<String, Object?>) '
          'constructor or static method, Map<String, Object?>, String or '
          'List<int>. [missing_from_json]',
      'lib/controllers/invalid_handlers.dart:39:8: error: Handler '
          'BrokenController.twoRoutes has more than one route annotation. '
          '[invalid_route_handler]',
      'lib/controllers/invalid_handlers.dart:43:15: error: Handler '
          'BrokenController.notInstance is static. '
          '[invalid_route_handler]',
      'lib/controllers/invalid_handlers.dart:47:5: error: Handler '
          'BrokenController.generic is generic. [invalid_route_handler]',
      'lib/controllers/invalid_handlers.dart:51:40: error: '
          "@Param('slug') of BrokenController.unknown is not in the route "
          'path; it declares id. [unknown_path_parameter]',
      'lib/controllers/invalid_handlers.dart:59:8: error: Route GET '
          '/broken/j/:b is declared twice: by BrokenController.first and '
          'by BrokenController.second. Parameter names do not distinguish '
          'routes. [duplicate_route]',
    ]);
  });
}
