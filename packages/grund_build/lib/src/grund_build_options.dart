import 'package:build/build.dart';
import 'package:grund_generator/grund_generator.dart';

import 'configuration_error_builder.dart';
import 'grund_builder.dart';

/// The options of `grund_build` in a package's `build.yaml`: the only
/// one, `package`, names the package, which build_runner does not tell a
/// builder before it builds; its output, `lib/<package>.grund.dart`,
/// must be declared before.
abstract final class GrundBuildOptions {
  /// The option that names the package.
  static const packageKey = 'package';

  /// The builder [options] configure: a [GrundBuilder] generating with
  /// [generator], or, when the options are missing or wrong, a builder that
  /// writes nothing and fails the build with what to put in `build.yaml`.
  static Builder builderFor(
    BuilderOptions options, {
    GrundGenerator generator = const GrundGenerator.core(),
  }) {
    final config = options.config;
    final unknown = [
      for (final key in config.keys)
        if (key != packageKey) key,
    ]..sort();
    if (unknown.isNotEmpty) {
      return ConfigurationErrorBuilder('unknown option ${unknown.join(', ')}');
    }
    return switch (config[packageKey]) {
      final String name when LibraryWriter.validPackageName.hasMatch(name) =>
        GrundBuilder(name, generator: generator),
      null => const ConfigurationErrorBuilder(
        'the option "package" is missing',
      ),
      final Object name => ConfigurationErrorBuilder(
        '"$name" is not a package name',
      ),
    };
  }

  /// The `build.yaml` that configures `grund_build` for [package].
  static String buildYaml(String package) =>
      'targets:\n'
      '  \$default:\n'
      '    builders:\n'
      '      grund_build:\n'
      '        options:\n'
      '          $packageKey: $package\n';
}
