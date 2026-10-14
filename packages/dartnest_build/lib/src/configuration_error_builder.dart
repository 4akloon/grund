import 'package:build/build.dart';

import 'dartnest_build_options.dart';

/// The builder that stands in for `dartnest_build` when its options in
/// `build.yaml` are missing or wrong: it writes nothing and fails the build
/// with [problem] and the `build.yaml` to write.
final class ConfigurationErrorBuilder implements Builder {
  /// Creates the builder that reports [problem].
  const ConfigurationErrorBuilder(this.problem);

  /// What is wrong with the options.
  final String problem;

  /// An output that is never written: build_runner 2.10 and build_test
  /// 3.5.5 skip a builder that declares none (the versions checked), and
  /// the build would pass silently.
  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$lib$': ['dartnest_build.unconfigured'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    log.severe(
      'dartnest_build cannot build $package: $problem. '
      'Name the package in its build.yaml:\n\n'
      '${DartnestBuildOptions.buildYaml(package)}',
    );
  }
}
