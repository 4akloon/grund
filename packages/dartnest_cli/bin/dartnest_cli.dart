import 'dart:io';

import 'package:dartnest_cli/dartnest_cli.dart';

/// Runs `dartnest_cli` with the core constructs.
Future<void> main(List<String> arguments) async {
  exitCode = await DartnestCli().run(arguments);
}
