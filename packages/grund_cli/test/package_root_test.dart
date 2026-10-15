import 'package:grund_cli/src/cli/cli_exit_code.dart';
import 'package:grund_cli/src/cli/cli_failure.dart';
import 'package:grund_cli/src/package/package_root.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/temp_dir.dart';

Matcher _noInput(String message) => isA<CliFailure>()
    .having((f) => f.exitCode, 'exitCode', CliExitCode.noInput)
    .having((f) => f.message, 'message', contains(message));

void main() {
  test('a package is read from its pubspec name', () {
    final dir = TempDir.create();
    dir.write('pubspec.yaml', 'name: shop\n');
    dir.write('lib/shop.dart', '');

    final package = PackageRoot.open(dir.path);

    expect(package.name, 'shop');
    expect(package.path, dir.path);
    expect(package.outputPath, dir.resolve('lib/shop.grund.dart'));
    expect(package.display(package.outputPath), 'lib/shop.grund.dart');
  });

  // Review Focus 1: run outside a package.
  test('a directory without pubspec.yaml is not a package', () {
    final dir = TempDir.create();

    expect(() => PackageRoot.open(dir.path), throwsA(_noInput('No pubspec')));
  });

  test('a pubspec without a valid name is rejected', () {
    final dir = TempDir.create();
    dir.write('lib/a.dart', '');

    dir.write('pubspec.yaml', 'name: Shop-App\n');
    expect(
      () => PackageRoot.open(dir.path),
      throwsA(_noInput('no valid package name')),
    );

    dir.write('pubspec.yaml', '- not a map\n');
    expect(
      () => PackageRoot.open(dir.path),
      throwsA(_noInput('no valid package name')),
    );

    dir.write('pubspec.yaml', 'name: [\n');
    expect(() => PackageRoot.open(dir.path), throwsA(_noInput('Cannot read')));
  });

  test('a package without lib/ has nothing to generate from', () {
    final dir = TempDir.create();
    dir.write('pubspec.yaml', 'name: shop\n');

    expect(() => PackageRoot.open(dir.path), throwsA(_noInput('No lib/')));
  });

  // Review Focus 8: diagnostics print `/` on every platform.
  test('paths are displayed with / separators', () {
    final dir = TempDir.create();
    dir.write('pubspec.yaml', 'name: shop\n');
    dir.write('lib/shop.dart', '');
    final nested = p.join(dir.path, 'lib', 'src', 'deep', 'a.dart');

    expect(PackageRoot.open(dir.path).display(nested), 'lib/src/deep/a.dart');
  });
}
