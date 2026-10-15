import 'dart:io';

import 'package:grund_cli/grund_cli.dart';

/// Runs `grund_cli` with the module and `@Api` constructs.
Future<void> main(List<String> arguments) async {
  exitCode = await GrundCli().run(arguments);
}
