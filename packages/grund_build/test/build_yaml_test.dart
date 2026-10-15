import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  // build_test runs one builder, so it cannot show the order of builders;
  // this pins the declaration that gives the order: build_runner runs a
  // builder with required_inputs only after the builders that write those
  // extensions, so types declared in generated parts (freezed,
  // json_serializable) resolve.
  test('grund_build runs after the builders that write .dart files', () {
    final yaml = loadYaml(File('build.yaml').readAsStringSync()) as YamlMap;
    final builder = (yaml['builders'] as YamlMap)['grund_build'] as YamlMap;

    expect(builder['required_inputs'], ['.dart']);
  });
}
