/// The complete value of the atomic `trip.expunge` setting.
enum TripExpungePolicy { never, age, count, size }

/// A validated retention policy for aggregate trip history.
///
/// The setting is deliberately modelled as one value because a policy and its
/// value must never be written separately.
class TripExpunge {
  const TripExpunge._(this.policy, this.value);

  const TripExpunge.never() : this._(TripExpungePolicy.never, null);

  /// Creates a strict policy/value pair or throws [FormatException].
  factory TripExpunge(TripExpungePolicy policy, [String? value]) {
    if (policy == TripExpungePolicy.never) {
      if (value != null) throw const FormatException('never has no value');
      return const TripExpunge.never();
    }
    if (value == null || !_validValue(policy, value)) {
      throw FormatException('Invalid ${policy.name} retention value');
    }
    return TripExpunge._(policy, value);
  }

  final TripExpungePolicy policy;
  final String? value;

  String get wireValue =>
      policy == TripExpungePolicy.never ? 'never' : '${policy.name}:$value';

  /// Parses only complete, canonical wire values.
  static TripExpunge parse(String wireValue) {
    if (wireValue == 'never') return const TripExpunge.never();
    final separator = wireValue.indexOf(':');
    if (separator <= 0 || separator != wireValue.lastIndexOf(':')) {
      throw const FormatException('Invalid trip expunge setting');
    }
    final policyName = wireValue.substring(0, separator);
    final value = wireValue.substring(separator + 1);
    TripExpungePolicy? policy;
    for (final candidate in TripExpungePolicy.values) {
      if (candidate.name == policyName) {
        policy = candidate;
        break;
      }
    }
    if (policy == null || policy == TripExpungePolicy.never) {
      throw const FormatException('Unknown trip expunge policy');
    }
    return TripExpunge(policy, value);
  }

  static bool _validValue(TripExpungePolicy policy, String value) {
    if (value.isEmpty || value.trim() != value) return false;
    switch (policy) {
      case TripExpungePolicy.never:
        return false;
      case TripExpungePolicy.age:
        return _isPositiveGoDurationOrDays(value);
      case TripExpungePolicy.count:
      case TripExpungePolicy.size:
        return _isCanonicalInt64(value);
    }
  }

  static bool _isCanonicalInt64(String value) {
    const maximum = '9223372036854775807';
    if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) return false;
    return value.length < maximum.length ||
        (value.length == maximum.length && value.compareTo(maximum) <= 0);
  }

  /// Validates exactly the positive subset of Go's int64-nanosecond duration
  /// grammar, without converting it to Dart's microsecond [Duration].
  static bool _isPositiveGoDurationOrDays(String value) {
    const nanosecondsPerDay = 86400000000000;
    const maximumNanoseconds = '9223372036854775807';
    final maximum = BigInt.parse(maximumNanoseconds);
    final days = RegExp(r'[1-9][0-9]*d').matchAsPrefix(value);
    if (days != null && days.end == value.length) {
      return BigInt.parse(value.substring(0, value.length - 1)) *
              BigInt.from(nanosecondsPerDay) <=
          maximum;
    }

    const units = <String, int>{
      'ns': 1,
      'us': 1000,
      'ms': 1000000,
      's': 1000000000,
      'm': 60000000000,
      'h': 3600000000000,
    };
    final segment = RegExp(r'((?:0|[1-9][0-9]*)(?:\.[0-9]+)?)(ns|us|ms|s|m|h)');
    var offset = 0;
    var total = BigInt.zero;
    while (offset < value.length) {
      final match = segment.matchAsPrefix(value, offset);
      if (match == null) return false;
      final number = match.group(1)!;
      final unit = BigInt.from(units[match.group(2)!]!);
      final decimal = number.indexOf('.');
      final whole = decimal < 0 ? number : number.substring(0, decimal);
      final fraction = decimal < 0 ? '' : number.substring(decimal + 1);
      total += BigInt.parse(whole) * unit;
      if (fraction.isNotEmpty) {
        total += BigInt.parse(fraction) *
            unit ~/
            BigInt.from(10).pow(fraction.length);
      }
      if (total > maximum) return false;
      offset = match.end;
    }
    return total > BigInt.zero;
  }

  @override
  bool operator ==(Object other) =>
      other is TripExpunge && other.policy == policy && other.value == value;

  @override
  int get hashCode => Object.hash(policy, value);

  @override
  String toString() => wireValue;
}
