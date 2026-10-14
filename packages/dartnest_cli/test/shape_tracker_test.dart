import 'package:dartnest_cli/src/dev/shape_tracker.dart';
import 'package:test/test.dart';

import 'helpers/temp_dir.dart';

const _service = '''
final greeting = 'hi';

final class Service {
  Service(this.name);

  final String name;

  String greet() => 'hello \$name';
}
''';

/// Whether replacing [from] by [to] in `_service` changes its shape.
bool changesShape(String from, String to) {
  expect(_service, contains(from));
  return ShapeTracker.shapeOf(_service) !=
      ShapeTracker.shapeOf(_service.replaceFirst(from, to));
}

void main() {
  group('ShapeTracker.shapeOf', () {
    test('a method body is not part of the shape', () {
      expect(changesShape("'hello \$name'", "'bye \$name'"), isFalse);
    });

    test('comments and formatting are not part of the shape', () {
      expect(
        changesShape(
          '  final String name;',
          '  // why\n  final String  name ;',
        ),
        isFalse,
      );
    });

    test('a new field changes the shape', () {
      // Review Focus 9: a reload keeps instances without the new field.
      expect(
        changesShape(
          '  final String name;',
          '  final String name;\n  int count = 0;',
        ),
        isTrue,
      );
    });

    test('a changed constructor changes the shape', () {
      expect(
        changesShape('Service(this.name);', 'Service([this.name = "x"]);'),
        isTrue,
      );
    });

    test('a changed top-level initializer changes the shape', () {
      expect(changesShape("greeting = 'hi'", "greeting = 'hello'"), isTrue);
    });

    test('a new enum value changes the shape', () {
      const before = 'enum Level { low }';
      expect(
        ShapeTracker.shapeOf(before),
        isNot(ShapeTracker.shapeOf('enum Level { low, high }')),
      );
    });

    test('a file with syntax errors still has a shape', () {
      expect(
        ShapeTracker.shapeOf('final class { int x = 1; '),
        contains('int x = 1;'),
      );
    });
  });

  group('ShapeTracker.changed', () {
    test('reports the files whose shape changed since remembered', () {
      final dir = TempDir.create();
      final service = dir.write('lib/service.dart', _service);
      final body = dir.write('lib/body.dart', _service);
      final tracker = ShapeTracker()..remember([service, body]);
      dir.write(
        'lib/service.dart',
        _service.replaceFirst(
          'final String name;',
          'final String name;\n  int count = 0;',
        ),
      );
      dir.write('lib/body.dart', _service.replaceFirst('hello', 'bye'));

      expect(tracker.changed([service, body]), [service]);
      expect(tracker.changed([service, body]), isEmpty);
    });

    test('new and deleted files are not shape changes', () {
      final dir = TempDir.create();
      final tracker = ShapeTracker();
      final added = dir.write('lib/added.dart', _service);

      expect(tracker.changed([added, dir.resolve('lib/gone.dart')]), isEmpty);
    });
  });
}
