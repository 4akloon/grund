import 'package:grund_http/grund_http.dart';

import '../page/page_alternate.dart';

/// Chooses between the HTML of a page and its alternates by `Accept`.
abstract final class AlternateNegotiation {
  /// The alternate that [accept] names and rates at least as high as
  /// `text/html`, the highest rated first and the first declared on a tie;
  /// `null` when the page itself is the answer.
  static PageAlternate? choose(
    AcceptHeader accept,
    List<PageAlternate> alternates,
  ) {
    final htmlQuality = accept.qualityOf('text/html');
    PageAlternate? best;
    var bestQuality = 0.0;
    for (final alternate in alternates) {
      if (!accept.names(alternate.mediaType)) continue;
      final quality = accept.qualityOf(alternate.mediaType);
      if (quality < htmlQuality || quality <= bestQuality) continue;
      best = alternate;
      bestQuality = quality;
    }
    return best;
  }
}
