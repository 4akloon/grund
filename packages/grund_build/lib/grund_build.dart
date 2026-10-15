/// The build_runner builder of grund: writes
/// `lib/<package>.grund.dart` from the annotations of a package, byte
/// for byte what `grund_cli gen` writes for the same sources.
///
/// `build.yaml` of this package applies [grundBuilder] to every package
/// that depends on `grund_build`; the package names itself in its own
/// `build.yaml` ([GrundBuildOptions]).
library;

import 'package:build/build.dart';

import 'src/grund_build_options.dart';

export 'src/grund_build_options.dart';
export 'src/grund_builder.dart';

/// The builder factory `build.yaml` names: the [Builder] that
/// [GrundBuildOptions.builderFor] makes from [options].
Builder grundBuilder(BuilderOptions options) =>
    GrundBuildOptions.builderFor(options);
