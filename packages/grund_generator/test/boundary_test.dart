import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Words that belong to `grund_http_generator`, never to the core.
const _forbidden = ['grund_http', 'HttpApi', 'HttpCtx', 'HookRef', 'Route'];

/// The HTTP annotations of `grund_http`; the core never reads them,
/// neither as `@Name` nor as a quoted name.
const _annotations = [
  'Api',
  'Get',
  'Post',
  'Put',
  'Patch',
  'Delete',
  'Path',
  'Query',
  'Header',
  'Cookie',
  'Body',
  'Range',
  'Length',
  'Pattern',
  'OneOf',
];

void main() {
  final sources = {
    for (final file in Directory('lib').listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart'))
        p.normalize(file.path): file.readAsStringSync(),
  };

  test('the core has sources to check', () {
    expect(sources.keys, contains(p.join('lib', 'grund_generator.dart')));
  });

  test('the core does not depend on an HTTP package', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, isNot(matches(RegExp(r'^\s*grund_http', multiLine: true))));
  });

  test('no core source mentions the HTTP part of the generator', () {
    final annotation = RegExp(
      '@(${_annotations.join('|')})\\b|'
      '[\'"](${_annotations.join('|')})[\'"]',
    );
    final found = [
      for (final MapEntry(key: path, value: source) in sources.entries)
        for (final (index, line) in source.split('\n').indexed)
          if (_forbidden.any(line.contains) || annotation.hasMatch(line))
            '$path:${index + 1}: $line',
    ];

    expect(found, isEmpty);
  });
}
