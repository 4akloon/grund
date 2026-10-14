/// The build_runner builder of dartnest: writes
/// `lib/<package>.dartnest.dart` from the annotations of a package, byte
/// for byte what `dartnest_cli gen` writes for the same sources.
///
/// [DartnestBuilder] is the builder; `build.yaml` of this package applies
/// it to every package that depends on `dartnest_build`.
library;

export 'src/dartnest_builder.dart';
