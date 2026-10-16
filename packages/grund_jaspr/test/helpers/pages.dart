import 'package:grund/grund.dart';
import 'package:grund_http/grund_http.dart';
import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart' hide Key;

/// Shows the URL Jaspr saw.
final class UrlPage extends StatelessComponent {
  const UrlPage();

  @override
  Component build(BuildContext context) =>
      Document(title: 'url', body: p([Component.text('url ${context.url}')]));
}

/// Sets two cookies and a header of its own.
final class CookiePage extends StatelessComponent {
  const CookiePage();

  @override
  Component build(BuildContext context) {
    context
      ..setCookie('a', '1')
      ..setCookie('b', '2')
      ..setHeader('x-page', 'yes');
    return Component.text('cookies');
  }
}

/// Answers XML with a status of its own.
final class FeedPage extends StatelessComponent {
  const FeedPage();

  @override
  Component build(BuildContext context) {
    context
      ..setHeader('content-type', 'application/xml')
      ..setHeader('Cache-Control', 'max-age=60')
      ..setStatusCode(203);
    return Component.text('feed');
  }
}

/// Throws while it is built.
final class BrokenPage extends StatelessComponent {
  const BrokenPage();

  @override
  Component build(BuildContext context) => throw StateError('secret detail');
}

/// A service a page reads from the call scope.
final class Greeter {
  /// The greeting.
  String greet() => 'hello from DI';
}

/// Exports [Greeter].
final class GreeterModule extends Module {
  const GreeterModule();

  @override
  List<Binding<Object>> get bindings => [
    Singleton<Greeter>((_) => Greeter(), dependsOn: const []),
  ];

  @override
  List<Object> get exports => const [Key<Greeter>()];
}

/// A value a hook puts into the call scope.
final class Visitor {
  const Visitor(this.name);

  final String name;
}

/// Sets the [Visitor] named by the `x-visitor` header.
final class VisitorHook extends HttpHook {
  const VisitorHook();

  @override
  void before(HttpCtx c) {
    if (c.headers.stringOrNull('x-visitor') case final name?) {
      c.set<Visitor>(Visitor(name));
    }
  }
}

/// Greets through DI and names the visitor a hook set.
final class ServicePage extends StatelessComponent {
  const ServicePage();

  @override
  Component build(BuildContext context) => Component.text(
    '${context.call<Greeter>().greet()}, '
    '${context.maybe<Visitor>()?.name ?? 'nobody'}',
  );
}

/// Reads the grund context where there is none.
final class ScopelessPage extends StatelessComponent {
  const ScopelessPage();

  @override
  Component build(BuildContext context) {
    try {
      context.injector;
      return Component.text('scope');
    } on MissingGrundScopeError {
      return Component.text('no scope');
    }
  }
}

/// Reads the cookie `flash` through grund, which tolerates a malformed
/// `Cookie` header of another application on the same host.
final class FlashPage extends StatelessComponent {
  const FlashPage();

  @override
  Component build(BuildContext context) => Component.text(
    'flash ${GrundScope.of(context).cookies.stringOrNull('flash')}',
  );
}
