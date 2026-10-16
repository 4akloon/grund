// Imports a module of another package through its public barrel.
import 'package:grund/grund.dart' as grund;
import 'package:grund/annotations.dart';
import 'package:other_pkg/other_pkg.dart';

/// Imports [OtherModule].
@Module(imports: [OtherModule()])
final class ViaBarrelModule extends grund.Module {
  /// Creates the module.
  const ViaBarrelModule();
}
