import 'package:grund/grund.dart';

/// A failure of `grund_jaspr`: setting Jaspr up or rendering a page.
abstract base class JasprError extends GrundError {
  /// Creates the error.
  const JasprError();
}

/// A page answered 500: a component threw while it was built (Jaspr printed
/// the error and its stack trace to stderr), or set the status 500 itself.
final class PageRenderError extends JasprError {
  /// Creates the error for the request [method] [path].
  const PageRenderError({required this.method, required this.path});

  /// The request method.
  final String method;

  /// The request path.
  final String path;

  @override
  String get message =>
      'The page $method $path failed to render: Jaspr answered 500. A '
      'component threw while it was built (Jaspr printed the error to '
      'stderr) or set the status 500.';
}

/// Jaspr is set up in a way `grund_jaspr` cannot render with.
final class JasprSetupError extends JasprError {
  /// Creates the error; [reason] says what is wrong and what to do.
  const JasprSetupError(this.reason);

  /// What is wrong and what to do.
  final String reason;

  @override
  String get message => 'Cannot render Jaspr pages: $reason';
}

/// A component asked for the grund context outside a page that
/// `JasprModule` renders.
final class MissingGrundScopeError extends JasprError {
  /// Creates the error.
  const MissingGrundScopeError();

  @override
  String get message =>
      'No GrundScope above this component: context.injector, context.call '
      'and context.maybe work only in pages that JasprModule renders.';
}
