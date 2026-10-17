import 'package:grund_jaspr/grund_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

/// The pages of the application, served at the root of the site.
///
/// Its shell makes every page, and the not-found answer, a document with
/// the stylesheet and the page title.
final class PublicSite extends PageSite {
  /// Creates the site.
  PublicSite(super.injector);

  @override
  Component shell(Component content) => Builder(
    builder: (context) => Document(
      title: context.pageMatch?.page.page.meta.title ?? 'Tasks',
      head: [link(href: '/static/styles.css', rel: 'stylesheet')],
      body: main_([content]),
    ),
  );

  @override
  Component notFound() => const Component.text('No page here.');
}
