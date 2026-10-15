// ignore_for_file: library_private_types_in_public_api
// The private types are the point of this fixture.
//
// A module that names private classes: generated code in another library
// cannot reach them.
import 'package:grund/grund.dart' as grund;
import 'package:grund/annotations.dart';

@Injectable()
final class _Hidden {}

final class _Secret {}

@Injectable()
final class Visible {
  Visible(this.hidden);

  final _Hidden hidden;
}

/// Provides a private class.
@Module(providers: [_Hidden, Visible])
final class PrivateModule extends grund.Module {
  /// Creates the module.
  const PrivateModule();

  /// A private return type.
  @Provides()
  static _Secret make() => _Secret();
}
