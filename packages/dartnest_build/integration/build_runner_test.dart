@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// The root of the generator's golden fixture `users_app`, whose
/// `build.yaml` configures `dartnest_build`.
Future<Directory> usersApp() async {
  final lib = await Isolate.resolvePackageUri(Uri.parse('package:users_app/'));
  if (lib == null) throw StateError('users_app is not in the package config.');
  return Directory.fromUri(lib.resolve('..'));
}

void main() {
  // The real build_runner, as a child process: it compiles the build
  // script (about 20 s the first time) and checks, writing nothing, that
  // the outputs it would write are the committed ones.
  test('build_runner generates the committed golden library', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'build_runner',
      'build',
      '--only-check',
    ], workingDirectory: (await usersApp()).path);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
