@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// The root of the generator's golden fixture `users_app`, which depends on
/// `grund_build` and needs no `build.yaml`.
Future<Directory> usersApp() async {
  final lib = await Isolate.resolvePackageUri(Uri.parse('package:users_app/'));
  if (lib == null) throw StateError('users_app is not in the package config.');
  return Directory.fromUri(lib.resolve('..'));
}

/// The version of build_runner the package config resolves, or `null`.
Future<(int, int)?> buildRunnerVersion() async {
  final config = await Isolate.packageConfig;
  if (config == null) return null;
  final json =
      jsonDecode(await File.fromUri(config).readAsString())
          as Map<String, Object?>;
  for (final package in json['packages']! as List<Object?>) {
    final entry = package! as Map<String, Object?>;
    if (entry['name'] != 'build_runner') continue;
    final match = RegExp(
      r'build_runner-(\d+)\.(\d+)',
    ).firstMatch(entry['rootUri']! as String);
    if (match == null) return null;
    return (int.parse(match[1]!), int.parse(match[2]!));
  }
  return null;
}

void main() {
  // The real build_runner, as a child process: it compiles the build
  // script (about 20 s the first time) and checks, writing nothing, that
  // the files it would write are the committed ones.
  test('build_runner generates the committed golden files', () async {
    final version = await buildRunnerVersion();
    if (version == null ||
        version.$1 < 2 ||
        (version.$1 == 2 && version.$2 < 16)) {
      markTestSkipped(
        'build --only-check needs build_runner 2.16 (Dart 3.11); '
        'resolved: ${version ?? 'unknown'}.',
      );
      return;
    }
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'build_runner',
      'build',
      '--only-check',
    ], workingDirectory: (await usersApp()).path);
    addTearDown(process.kill);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();

    final exitCode = await process.exitCode;

    expect(exitCode, 0, reason: '${await stdout}\n${await stderr}');
  });
}
