import 'package:tasks_api/tasks_api.dart';
import 'package:test/test.dart';

void main() {
  test('no arguments: annotations, dart:io, port 8080', () {
    final options = ServerOptions.parse(const [], const {});

    expect(options.style, ModuleStyle.annotations);
    expect(options.adapter, AdapterKind.io);
    expect(options.port, 8080);
  });

  test('--explicit --shelf and PORT', () {
    final options = ServerOptions.parse(
      const ['--shelf', '--explicit'],
      const {'PORT': '9090'},
    );

    expect(options.style, ModuleStyle.explicit);
    expect(options.adapter, AdapterKind.shelf);
    expect(options.port, 9090);
  });

  test('an unknown argument is a FormatException with the usage', () {
    expect(
      () => ServerOptions.parse(const ['--port=1'], const {}),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('--port=1'), contains(ServerOptions.usage)),
        ),
      ),
    );
  });

  test('a PORT outside 1 to 65535 is a FormatException', () {
    for (final port in ['0', '65536', 'http']) {
      expect(
        () => ServerOptions.parse(const [], {'PORT': port}),
        throwsFormatException,
        reason: port,
      );
    }
  });
}
