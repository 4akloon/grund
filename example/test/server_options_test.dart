import 'package:grund/grund.dart';
import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

void main() {
  test('no arguments: annotations, dart:io, port 8080', () {
    final options = ServerOptions.parse(const [], const Environment({}));

    expect(options.style, ModuleStyle.annotations);
    expect(options.adapter, AdapterKind.io);
    expect(options.address, 'localhost');
    expect(options.port, 8080);
  });

  test('--explicit --shelf and PORT', () {
    final options = ServerOptions.parse(const [
      '--shelf',
      '--explicit',
    ], const Environment({'HOST': '127.0.0.1', 'PORT': '9090'}));

    expect(options.style, ModuleStyle.explicit);
    expect(options.adapter, AdapterKind.shelf);
    expect(options.address, '127.0.0.1');
    expect(options.port, 9090);
  });

  test('an unknown argument is a FormatException with the usage', () {
    expect(
      () => ServerOptions.parse(const ['--port=1'], const Environment({})),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('--port=1'), contains(ServerOptions.usage)),
        ),
      ),
    );
  });

  test('PORT=0 picks a free port', () {
    final options = ServerOptions.parse(
      const [],
      const Environment({'PORT': '0'}),
    );

    expect(options.port, 0);
  });

  test('a bad PORT is an InvalidVariableError', () {
    for (final port in ['65536', 'http', '+80', ' 80', '']) {
      expect(
        () => ServerOptions.parse(const [], Environment({'PORT': port})),
        throwsA(
          isA<InvalidVariableError>().having((e) => e.name, 'name', 'PORT'),
        ),
        reason: port,
      );
    }
  });

  test('an empty HOST is an InvalidVariableError', () {
    expect(
      () => ServerOptions.parse(const [], const Environment({'HOST': ''})),
      throwsA(
        isA<InvalidVariableError>().having((e) => e.name, 'name', 'HOST'),
      ),
    );
  });
}
