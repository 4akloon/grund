@Timeout(Duration(minutes: 5))
library;

import 'package:test/test.dart';

import '../test/helpers/temp_package.dart';
import 'dev_jaspr_test.dart' show page;
import 'helpers/dev_run.dart';
import 'helpers/site_sources.dart';
import 'helpers/startup_events.dart';

const _bundle = 'web/client/main.client.dart.js';

// Valid syntax, so generation passes; the compiler rejects the type.
const _broken = 'void main() { int x = "text"; }';

String _client(String text) => 'void main() { print("$text"); }';

Future<TempPackage> _site(String client, {String? main}) =>
    TempPackage.create('site', {
      ...SiteSources.files,
      'bin/main.dart': ?main,
      'lib/main.client.dart': client,
    });

void main() {
  test('the bundle exists before serving; a change rebuilds it before the '
      'reload', () async {
    final package = await _site(
      _client('client-one'),
      main: StartupEvents.main,
    );
    final (:dev, :events) = await StartupEvents.start(package.dir.path);
    expect(package.dir.read(_bundle), contains('client-one'));

    package.dir.write('lib/main.client.dart', _client('client-two'));

    expect(await events.nextEvent(), 'reload');
    expect(package.dir.read(_bundle), contains('client-two'));
    await dev.stop();
  });

  test('a change that does not compile keeps the old bundle, prints the '
      'error and still reloads', () async {
    final package = await _site(
      _client('client-one'),
      main: StartupEvents.main,
    );
    final (:dev, :events) = await StartupEvents.start(package.dir.path);

    package.dir.write('lib/main.client.dart', _broken);

    expect(await events.nextEvent(), 'reload');
    expect(package.dir.read(_bundle), contains('client-one'));
    // The child's stdout and the event stream are different channels.
    await until(dev.lines, (line) => line.contains('Client bundle failed'));
    await dev.stop();
  });

  test('a first build that fails still starts the application', () async {
    final package = await _site(_broken);
    final dev = await DevRun.start(package.dir.path, port: await freePort());

    expect(await page(dev.port), contains('page v1'));
    // The child's stdout and the event stream are different channels.
    await until(dev.lines, (line) => line.contains('Client bundle failed'));
    await dev.stop();
  });
}
