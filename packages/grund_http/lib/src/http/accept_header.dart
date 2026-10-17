/// The media ranges of an `Accept` request header with their qualities
/// (RFC 9110 §12.5.1). Reading never throws.
final class AcceptHeader {
  AcceptHeader._(this._ranges, {required this.isAbsent});

  /// Reads [value], every `Accept` field of the request joined with `,`.
  /// `null`, empty or blank means the header is absent.
  factory AcceptHeader.parse(String? value) {
    if (value == null || value.trim().isEmpty) {
      return AcceptHeader._(const {}, isAbsent: true);
    }
    final ranges = <String, double>{};
    for (final element in value.split(',')) {
      final parts = element.split(';');
      final range = parts.first.trim().toLowerCase();
      if (!_range.hasMatch(range)) continue;
      final quality = _quality(parts.skip(1));
      final known = ranges[range];
      if (known == null || quality > known) ranges[range] = quality;
    }
    return AcceptHeader._(ranges, isAbsent: false);
  }

  /// Whether the header was absent, empty or blank: everything is accepted.
  final bool isAbsent;

  final Map<String, double> _ranges;

  static final _range = RegExp(
    r"^(\*/\*|[!#$%&'*+.^_`|~0-9A-Za-z-]+/(\*|[!#$%&'*+.^_`|~0-9A-Za-z-]+))$",
  );
  static final _weight = RegExp(r'^(0(\.\d{0,3})?|1(\.0{0,3})?)$');

  /// The quality of [mediaType] (`type/subtype`, case-insensitive): that of
  /// the most specific range matching it (`type/subtype`, then `type/*`,
  /// then `*/*`); 0 when none matches; 1 when the header is absent.
  double qualityOf(String mediaType) {
    if (isAbsent) return 1;
    final type = mediaType.toLowerCase();
    final wildcard = '${type.split('/').first}/*';
    return _ranges[type] ?? _ranges[wildcard] ?? _ranges['*/*'] ?? 0;
  }

  /// Whether the header names [mediaType] itself (not through a wildcard)
  /// with a quality above 0.
  bool names(String mediaType) => (_ranges[mediaType.toLowerCase()] ?? 0) > 0;

  /// The `q` parameter among [parameters]; 1 without one, 0 when malformed.
  static double _quality(Iterable<String> parameters) {
    for (final parameter in parameters) {
      final separator = parameter.indexOf('=');
      if (separator < 0) continue;
      if (parameter.substring(0, separator).trim().toLowerCase() != 'q') {
        continue;
      }
      final weight = parameter.substring(separator + 1).trim();
      return _weight.hasMatch(weight) ? double.parse(weight) : 0;
    }
    return 1;
  }
}
