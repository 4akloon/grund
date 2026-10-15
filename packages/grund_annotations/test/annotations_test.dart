import 'package:grund_annotations/grund_annotations.dart';
import 'package:test/test.dart';

void main() {
  test('Module defaults to an empty, non-global module', () {
    const module = Module();

    expect(module.imports, isEmpty);
    expect(module.providers, isEmpty);
    expect(module.exports, isEmpty);
    expect(module.global, isFalse);
  });

  test('Injectable and Provides default to the singleton scope', () {
    expect(const Injectable().scope, Scope.singleton);
    expect(const Provides().scope, Scope.singleton);
    expect(const Injectable(scope: Scope.call).scope, Scope.call);
    expect(const Provides(scope: Scope.transient).scope, Scope.transient);
  });

  test('Api keeps its path and hooks; Named keeps its name', () {
    const api = Api('/tasks', use: [#hook]);

    expect(api.path, '/tasks');
    expect(api.use, [#hook]);
    expect(const Named('primary').name, 'primary');
  });

  test('route annotations carry method, path, status and hooks', () {
    const routes = <RouteAnnotation>[
      Get('/:id'),
      Post('/', status: 201, use: [#roles]),
      Put('/a'),
      Patch('/b'),
      Delete('/c'),
    ];

    expect(
      [for (final r in routes) '${r.method} ${r.path} ${r.status} ${r.use}'],
      [
        'GET /:id null []',
        'POST / 201 [Symbol("roles")]',
        'PUT /a null []',
        'PATCH /b null []',
        'DELETE /c null []',
      ],
    );
  });

  test('parameter annotations name the request part', () {
    const parameters = <ParameterAnnotation>[
      Path(),
      Query(name: 'page_size'),
      Header(name: 'x-key'),
      Cookie(),
      Body(),
    ];

    expect(
      [for (final parameter in parameters) parameter.name],
      [null, 'page_size', 'x-key', null, null],
    );
  });

  test('validator annotations hold their bounds', () {
    const range = Range(min: 1, max: 100);
    const length = Length(max: 8);

    expect((range.min, range.max, length.min, length.max), (1, 100, null, 8));
    expect(const Pattern(r'^\d+$').regex, r'^\d+$');
    expect(const OneOf(['a', 'b']).values, ['a', 'b']);
  });

  test('Bind has the interface and the implementation as type arguments', () {
    expect(
      const Bind<Object, String>().runtimeType.toString(),
      'Bind<Object, String>',
    );
  });
}
