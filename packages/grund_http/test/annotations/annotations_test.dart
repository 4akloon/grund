import 'package:grund_http/annotations.dart';
import 'package:test/test.dart';

void main() {
  test('Api keeps its path and hooks', () {
    const api = Api('/tasks', use: [#hook]);

    expect(api.path, '/tasks');
    expect(api.use, [#hook]);
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
}
