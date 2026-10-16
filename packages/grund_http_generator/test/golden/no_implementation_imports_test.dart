import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  test('no committed generated file of users_app imports the src/ of another '
      'package', () {
    final root = FixturePackage.open('users_app').root;
    final imports = RegExp(r'''^import 'package:(\w+)/src/''', multiLine: true);
    final offenders = [
      for (final file in Directory(
        p.join(root, 'lib'),
      ).listSync(recursive: true))
        if (file is File && file.path.endsWith('.g.dart'))
          for (final match in imports.allMatches(file.readAsStringSync()))
            if (match.group(1) != 'users_app')
              '${p.relative(file.path, from: root)}: ${match.group(0)}',
    ];

    expect(offenders, isEmpty);
  });
}
