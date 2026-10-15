// Dependencies that cannot be resolved, and one that resolves through a
// global module.
import 'package:grund/grund.dart' hide Controller, Module;
import 'package:grund_annotations/grund_annotations.dart';

import '../controllers/components.dart';
import '../modules/basic.dart';

/// Needs a [Wheel].
@Injectable()
final class Engine {
  /// Creates it.
  Engine(this.wheel);

  /// The wheel.
  final Wheel wheel;
}

/// Needs an [Engine].
@Injectable()
final class Wheel {
  /// Creates it.
  Wheel(this.engine);

  /// The engine.
  final Engine engine;
}

/// The SMTP URL; nobody provides it.
const smtpUrl = Token<String>('smtp.url');

/// Needs a clock, which only `DbModule` declares, and an unprovided token.
@Injectable()
final class Mailer {
  /// Creates it.
  Mailer(this.clock, @Inject(smtpUrl) this.url, this.repo);

  /// The clock.
  final Clock clock;

  /// The SMTP URL.
  final String url;

  /// The repository, exported by the global `DbModule`.
  final Repo repo;
}

/// Needs a [Mailer] and is guarded by an unprovided guard.
@Controller('/mail')
@UseGuards([OpenGuard])
final class MailController {
  /// Creates it.
  MailController(this.mailer, this.engine);

  /// The mailer.
  final Mailer mailer;

  /// Not visible in `MailModule`.
  final Engine engine;

  /// Sends nothing.
  @Post()
  void send() {}
}

/// Two classes that need each other.
@Module(providers: [Engine, Wheel])
class CarModule {}

/// A mailer without its dependencies.
@Module(providers: [Mailer], controllers: [MailController])
class MailModule {}
