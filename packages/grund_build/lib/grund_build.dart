/// The build_runner builder of grund: writes `X.g.dart` next to
/// every library that declares `@Module` or `@Api`,
/// byte for byte what `grund_cli gen` writes for the same sources.
///
/// `build.yaml` of this package applies [grundBuilder] to every package
/// that depends on `grund_build`; it needs no options.
library;

import 'package:build/build.dart';

import 'src/grund_builder.dart';

export 'src/grund_builder.dart';

/// The builder factory `build.yaml` names: the [GrundBuilder] that runs
/// the constructs `grund_cli` runs. It takes no options.
Builder grundBuilder(BuilderOptions options) => const GrundBuilder();
