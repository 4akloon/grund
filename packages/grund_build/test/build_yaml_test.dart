import 'dart:io';

import 'package:grund_build/grund_build.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

YamlMap _builder() {
  final yaml = loadYaml(File('build.yaml').readAsStringSync()) as YamlMap;
  return (yaml['builders'] as YamlMap)['grund_build'] as YamlMap;
}

void main() {
  // build_test runs one builder, so it cannot show the order of builders;
  // this pins the declaration that gives the order: build_runner runs a
  // builder with required_inputs only after the builders that write those
  // extensions, so types declared in generated parts (freezed,
  // json_serializable) resolve.
  test('grund_build runs after the builders that write .dart files', () {
    expect(_builder()['required_inputs'], ['.dart']);
  });

  // build.yaml declares what the builder class says; build_runner trusts
  // the file, so a difference would write undeclared files or none.
  test('build.yaml declares the extensions of the builder class', () {
    final declared = (_builder()['build_extensions'] as YamlMap).map(
      (key, value) => MapEntry(key, (value as YamlList).toList()),
    );

    expect(declared, GrundBuilder().buildExtensions);
  });

  test('the outputs are written into the source tree', () {
    expect(_builder()['build_to'], 'source');
    expect(_builder()['auto_apply'], 'dependents');
  });
}
