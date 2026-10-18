import 'fullstack_template.dart';
import 'project_template.dart';

/// Which application `init` writes (`--template`).
enum ProjectKind {
  /// A JSON API written with annotations; the default.
  api('A JSON API written with annotations.'),

  /// Server-rendered Jaspr pages with cookie sessions, written with the
  /// explicit API.
  fullstack('Server-rendered Jaspr pages with cookie sessions.');

  const ProjectKind(this.summary);

  /// One line for `init --help`.
  final String summary;

  /// The files of application [name] (relative path to content), sorted by
  /// path.
  Map<String, String> files(String name) => switch (this) {
    ProjectKind.api => ProjectTemplate.files(name),
    ProjectKind.fullstack => FullstackTemplate.files(name),
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
    ProjectKind.fullstack => const {
      'grund',
      'grund_auth',
      'grund_cli',
      'grund_http',
      'grund_io',
      'grund_jaspr',
      'jaspr',
      'lints',
      'test',
    },
  };

  /// The commands `init` suggests after `dart pub get`.
  List<String> get nextSteps => switch (this) {
    ProjectKind.api => const [
      'dart run grund_cli gen',
      'dart run bin/main.dart',
    ],
    ProjectKind.fullstack => const [
      'dart run grund_cli dev',
      'dart run grund_cli bundle  # production bundle (-O2) for /static/client/',
    ],
  };
}
