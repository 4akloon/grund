import 'dart:io';

import 'package:dartnest_cli/dartnest_cli.dart';
import 'package:dartnest_generator/dartnest_generator.dart';

import '../../test/helpers/exploding_construct.dart';

/// The command line with a generator whose runs fail, for the integration
/// test that `dev` exits on a failure instead of hanging.
Future<void> main(List<String> arguments) async {
  exitCode = await DartnestCli(
    generator: const DartnestGenerator([ExplodingConstruct()]),
  ).run(arguments);
}
