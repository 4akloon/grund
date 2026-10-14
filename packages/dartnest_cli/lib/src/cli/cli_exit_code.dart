/// The exit codes of `dartnest_cli`, taken from BSD `sysexits.h` where one
/// fits.
enum CliExitCode {
  /// The command did what it was asked.
  success(0),

  /// The sources have problems: generator diagnostics or syntax errors.
  problems(1),

  /// The command line is wrong.
  usage(64),

  /// The package to work on is missing or unreadable.
  noInput(66),

  /// An internal failure: a generation run, the application process or a key
  /// action of `dev` failed in a way the tool does not handle.
  software(70),

  /// A file cannot be written.
  cannotCreate(73),

  /// `dev` was interrupted a second time while it was shutting down.
  interrupted(130);

  const CliExitCode(this.code);

  /// The process exit code.
  final int code;
}
