// Constants for ConstantReader tests: each annotation on [Holder] is read
// by name.
import 'package:grund/grund.dart' show Key;
import 'package:grund_annotations/grund_annotations.dart';

/// A value object with a public constant.
final class Label {
  /// Creates the label.
  const Label(this.name);

  /// The label text.
  final String name;
}

/// A public constant.
const dbLabel = Label('db.url');

const _secret = Label('secret');

/// Something that is built from a named constructor and has a type argument.
final class Ref<T extends Object> {
  /// A reference by type.
  const Ref.type() : value = null;

  /// A reference to a given value.
  const Ref.instance(this.value);

  /// The value, if any.
  final T? value;
}

/// Marks something for the tests.
abstract class Marker {
  /// Creates the marker.
  const Marker();
}

/// Statuses.
enum Status { active, banned }

/// Metadata with every kind of field.
final class Tagged extends Marker {
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
final class Wrapped extends Marker {
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
@Named('db')
@Wrapped(_secret)
@Wrapped(Ref<Holder>.instance(Holder()))
@Wrapped(Key<Holder>('main'))
@Api('/holder', use: [#guard])
class Holder {
  /// Creates the holder.
  const Holder();
}
