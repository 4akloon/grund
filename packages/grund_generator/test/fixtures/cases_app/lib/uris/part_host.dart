// A library whose part file declares a module.
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

part 'part_host_module.dart';

/// A module in the library file.
@Module()
final class HostModule extends grund.Module {
  /// Creates the module.
  const HostModule();
}
