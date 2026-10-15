/// Which module graph `bin/main.dart` serves.
enum ModuleStyle {
  /// `AppModule`, declared with annotations (its glue is generated).
  annotations,

  /// `ExplicitAppModule`, written by hand with the explicit API.
  explicit,
}
