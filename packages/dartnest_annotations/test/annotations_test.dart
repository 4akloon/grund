import 'package:dartnest_annotations/dartnest_annotations.dart';
import 'package:test/test.dart';

final class _Roles extends RouteMetadata {
  const _Roles(this.names);
  final List<String> names;
}

void main() {
  test('Module defaults to an empty, non-global module named by its class', () {
    const module = Module();

    expect(module.id, isNull);
    expect(module.imports, isEmpty);
    expect(module.providers, isEmpty);
    expect(module.controllers, isEmpty);
    expect(module.exports, isEmpty);
    expect(module.global, isFalse);
  });

  test('route annotations carry their HTTP method and path', () {
    const routes = <RouteAnnotation>[
      Get('/:id'),
      Post(),
      Put('/a'),
      Patch('/b'),
      Delete('/c'),
    ];

    expect(
      [for (final route in routes) '${route.method} ${route.path}'],
      ['GET /:id', 'POST ', 'PUT /a', 'PATCH /b', 'DELETE /c'],
    );
  });

  test('argument annotations name the request part', () {
    const arguments = <ArgumentAnnotation>[
      Param('id'),
      Query('limit'),
      Header('authorization'),
      Body(),
    ];

    final names = [
      for (final argument in arguments)
        switch (argument) {
          Param(:final name) => 'param $name',
          Query(:final name) => 'query $name',
          Header(:final name) => 'header $name',
          Body() => 'body',
        },
    ];
    expect(names, ['param id', 'query limit', 'header authorization', 'body']);
  });

  test('component annotations keep the types in order', () {
    const guards = UseGuards([int, String]);
    const filters = UseFilters([double]);

    expect(guards.types, [int, String]);
    expect(filters.types, [double]);
  });

  test('provider annotations hold their constants', () {
    const value = Value('postgres://localhost', token: #db);
    const inject = Inject(#db);

    expect(
      (value.value, value.token, inject.token),
      ('postgres://localhost', #db, #db),
    );
    expect(
      const Bind<Object, String>().runtimeType.toString(),
      'Bind<Object, String>',
    );
  });

  test('Controller defaults to an empty path; RouteMetadata is const', () {
    expect(const Controller().path, '');
    expect(const Controller('/users').path, '/users');
    expect(const _Roles(['admin']).names, ['admin']);
  });
}
