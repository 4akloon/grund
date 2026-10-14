/// The build_runner builder of dartnest: writes
/// `lib/<package>.dartnest.dart` from the annotations of a package, byte
/// for byte what `dartnest_cli gen` writes for the same sources.
///
/// `build.yaml` of this package applies [dartnestBuilder] to every package
/// that depends on `dartnest_build`; the package names itself in its own
/// `build.yaml` ([DartnestBuildOptions]).
library;

import 'package:build/build.dart';

import 'src/dartnest_build_options.dart';

export 'src/dartnest_build_options.dart';
export 'src/dartnest_builder.dart';

/// The builder factory `build.yaml` names: the [Builder] that
/// [DartnestBuildOptions.builderFor] makes from [options].
Builder dartnestBuilder(BuilderOptions options) =>
    DartnestBuildOptions.builderFor(options);
