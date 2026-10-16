import 'project_template.dart';

/// Which application `init` writes.
enum ProjectKind {
  /// A JSON API written with annotations.
  api;

  /// The files of application [name] (relative path to content), sorted by
  /// path.
  Map<String, String> files(String name) => switch (this) {
    ProjectKind.api => ProjectTemplate.files(name),
  };

  /// The packages the new pubspec names; the new package cannot take one
  /// of these names.
  Set<String> get dependencies => switch (this) {
    ProjectKind.api => const {
      'grund',
      'grund_cli',
      'grund_http',
      'grund_io',
      'lints',
      'test',
    },
  };
}
