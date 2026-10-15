// A library that declares both a module and an API: each needs the one
// output file `module_and_api.g.dart`, so it is a conflicting_outputs and
// the file is never generated.
// ignore_for_file: uri_has_not_been_generated
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

part 'module_and_api.g.dart';

/// Answers pings.
@Api('/both')
final class BothApi {
  /// Pong.
  @Get('/')
  String ping(http.HttpCtx c) => 'pong';
}

/// Provides the API of its own library.
@Module(providers: [BothApi])
final class BothModule extends grund.Module {
  /// Creates the module.
  const BothModule();
}
