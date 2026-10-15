// Like `module_and_api.dart`, but without `part 'module_and_api_no_part.g.dart';`:
// only conflicting_outputs is reported, since a part could never be valid.
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

/// Answers pings.
@Api('/both')
final class BothNoPartApi {
  /// Pong.
  @Get('/')
  String ping(http.HttpCtx c) => 'pong';
}

/// Provides the API of its own library.
@Module(providers: [BothNoPartApi])
final class BothNoPartModule extends grund.Module {
  /// Creates the module.
  const BothNoPartModule();
}
