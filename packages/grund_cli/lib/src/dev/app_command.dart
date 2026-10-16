/// The command line of the application process: `dart <entry> <arguments>`
/// in [workingDirectory], with [environment] added to the environment of
/// `dev`.
final class AppCommand {
  /// Creates the command.
  const AppCommand(
    this.entry, {
    required this.workingDirectory,
    this.arguments = const [],
    this.environment = const {},
  });

  /// The entry point, absolute or relative to [workingDirectory].
  final String entry;

  /// The directory the process starts in.
  final String workingDirectory;

  /// The arguments of the application's `main`.
  final List<String> arguments;

  /// Variables added to the environment `dev` itself runs with.
  final Map<String, String> environment;
}
