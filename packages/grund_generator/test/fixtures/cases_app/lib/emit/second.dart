// A second library with a module, for one-output-per-library tests.
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';

/// A service of the second library.
@Injectable()
final class Mailer {}

/// The module of the second library.
@Module(providers: [Mailer], exports: [Mailer])
final class EmitMailModule extends grund.Module {
  /// Creates the module.
  const EmitMailModule();
}
