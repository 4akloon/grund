import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';

/// Dart source text compared by content: both sides go through the same
/// `DartFormatter`, so a difference in how two `dart_style` releases lay
/// out the same code (trailing closures, for one) does not fail a check,
/// while any change of content does.
abstract final class NormalizedSource {
  /// The language version the generator formats with (the package's).
  static final languageVersion = Version(3, 8, 0);

  /// [source] formatted again.
  static String of(String source) =>
      DartFormatter(languageVersion: languageVersion).format(source);

  /// [files] with every content normalised.
  static Map<String, String> allOf(Map<String, String> files) => {
    for (final MapEntry(:key, :value) in files.entries) key: of(value),
  };
}
