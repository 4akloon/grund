import 'dart:io';

import 'package:grund_cli/grund_cli.dart';
import 'package:grund_generator/grund_generator.dart';

import '../../test/helpers/exploding_construct.dart';

/// The command line with a generator whose runs fail, for the integration
/// test that `dev` exits on a failure instead of hanging.
Future<void> main(List<String> arguments) async {
  exitCode = await GrundCli(
    generator: const GrundGenerator([ExplodingConstruct()]),
  ).run(arguments);
}
