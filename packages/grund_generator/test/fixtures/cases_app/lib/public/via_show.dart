// Shows the module from the barrel.
import 'package:grund/grund.dart' as grund;
import 'package:grund/annotations.dart';
import 'package:other_pkg/other_pkg.dart' show OtherModule;

/// Imports OtherModule.
@Module(imports: [OtherModule()])
final class ViaShowModule extends grund.Module {
  /// Creates the module.
  const ViaShowModule();
}
