/// Which module graph `bin/main.dart` serves.
enum ModuleStyle {
  /// `appModule` from the library generated from the annotations.
  annotations,

  /// `explicitAppModule`, written by hand with the explicit API.
  explicit,
}
