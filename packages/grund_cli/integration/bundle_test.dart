@Timeout(Duration(minutes: 5))
library;

import 'package:test/test.dart';

import '../test/helpers/cli_run.dart';
import '../test/helpers/temp_package.dart';

Future<CliRun> _bundle(TempPackage package, [List<String> extra = const []]) =>
    CliRun.run(['bundle', '-C', package.dir.path, ...extra]);

void main() {
  test('bundle creates the production bundle without maps or deps', () async {
    final package = await TempPackage.create('site', {
      'lib/main.client.dart': 'void main() {}',
    });

    final run = await _bundle(package);

    expect(run.exitCode, 0, reason: run.err);
    expect(package.dir.exists('web/client/main.client.dart.js'), isTrue);
    expect(package.dir.exists('web/client/main.client.dart.js.map'), isFalse);
    expect(package.dir.exists('web/client/main.client.dart.js.deps'), isFalse);
  });

  test('a second build after a change updates the file', () async {
    final package = await TempPackage.create('site', {
      'lib/main.client.dart': 'void main() { print("first"); }',
    });
    await _bundle(package);
    final first = package.dir.read('web/client/main.client.dart.js');

    package.dir.write(
      'lib/main.client.dart',
      'void main() { print("second"); }',
    );
    final run = await _bundle(package);

    expect(run.exitCode, 0, reason: run.err);
    final second = package.dir.read('web/client/main.client.dart.js');
    expect(second, isNot(first));
    expect(second, contains('second'));
  });

  test('--entry bundles another file under its own name', () async {
    final package = await TempPackage.create('site', {
      'lib/other.client.dart': 'void main() {}',
    });

    final run = await _bundle(package, ['--entry', 'lib/other.client.dart']);

    expect(run.exitCode, 0, reason: run.err);
    expect(package.dir.exists('web/client/other.client.dart.js'), isTrue);
    expect(package.dir.exists('web/client/other.client.dart.js.deps'), isFalse);
  });
}
