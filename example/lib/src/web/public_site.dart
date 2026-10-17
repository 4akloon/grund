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

  static const _htmxConfig =
      '{"responseHandling":['
      '{"code":"204","swap":false},'
      '{"code":"[23]..","swap":true},'
      '{"code":"422","swap":true},'
      '{"code":"[45]..","swap":false,"error":true}]}';

  @override
  Component shell(Component content) => Builder(
    builder: (context) => Document(
      title: context.pageMatch?.meta.title ?? 'Tasks',
      head: [
        link(href: '/static/styles.css', rel: 'stylesheet'),
        // htmx swaps a 422 (a refused title) like a success and leaves
        // other 4xx and 5xx answers alone.
        meta(name: 'htmx-config', content: _htmxConfig),
        script(src: '/static/vendor/htmx.min.js', defer: true),
      ],
      body: main_([content]),
    ),
  );

  @override
  Component notFound() => const Component.text('No page here.');
}
