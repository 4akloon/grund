// Constants for ConstantReader tests: each annotation on [Holder] is read
// by name.
import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

/// A public token.
const dbUrl = Token<String>('db.url');

const _secret = Token<int>('secret');

/// Statuses.
enum Status { active, banned }

/// Metadata with every kind of field.
final class Tagged extends RouteMetadata {
  /// Creates the metadata.
  const Tagged(
    this.label, {
    this.count = 0,
    this.ratio = 0.5,
    this.flags = const {},
    this.extra = const {},
    this.status,
    this.type,
    this.nothing,
  });

  /// A string.
  final String label;

  /// An int.
  final int count;

  /// A double.
  final double ratio;

  /// A set.
  final Set<String> flags;

  /// A map.
  final Map<String, int> extra;

  /// An enum value.
  final Status? status;

  /// A type.
  final Type? type;

  /// Always null.
  final Object? nothing;
}

/// Metadata holding a private object.
final class Wrapped extends RouteMetadata {
  /// Creates the metadata.
  const Wrapped(this.value);

  /// The wrapped value.
  final Object value;
}

final class _Hidden {
  const _Hidden();
}

/// Carries the annotations the tests read.
@Tagged(
  'it\'s \$5',
  count: 3,
  flags: {'a'},
  extra: {'x': 1},
  status: Status.banned,
  type: Holder,
)
@Wrapped(_Hidden())
@Inject(dbUrl)
@Value(_secret)
@UseGuards([Holder])
class Holder {}
