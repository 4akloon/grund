import 'dart:convert';
import 'dart:io';

import 'package:grund_cli/grund_cli.dart';

import 'dev_sources.dart';
import 'temp_package.dart';

/// The generated `hello` application ([DevSources]) in a [TempPackage].
final class HelloApp {
  HelloApp._(this.package);

  /// Creates the package and generates its library.
  static Future<HelloApp> create() async {
    final package = await TempPackage.create('hello', DevSources.files);
    final session = GenerationSession(package.root);
    try {
      final report = await session.run();
      if (report.hasProblems) throw StateError('${report.problemLines}');
    } finally {
      await session.close();
    }
    return HelloApp._(package);
  }

  /// The package.
  final TempPackage package;

  /// Replaces [from] by [to] in the package file [relative].
  void edit(String relative, String from, String to) {
    final source = package.dir.read(relative);
    if (!source.contains(from)) throw StateError('No "$from" in $relative.');
    package.dir.write(relative, source.replaceFirst(from, to));
  }

  /// The port in a `listening on <port>` line, or `null`.
  static int? portIn(String line) => switch (line.split(' ')) {
    ['listening', 'on', final port] => int.tryParse(port),
    _ => null,
  };

  /// The JSON answer of `GET <path>` on 127.0.0.1:[port], or the status
  /// code when it is not 200.
  static Future<Object?> get(int port, String path) async {
    final client = HttpClient();
    try {
      final request = await client.get('127.0.0.1', port, path);
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      return response.statusCode == 200
          ? jsonDecode(body)
          : response.statusCode;
    } finally {
      client.close(force: true);
    }
  }
}
