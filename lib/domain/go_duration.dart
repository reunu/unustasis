// Helpers for Go `time.Duration` strings as used by librescoot settings
// (e.g. "8h", "1h30m", "28800s").

final RegExp _segment = RegExp(r'^(\d+(?:\.\d+)?)(ns|us|µs|μs|ms|s|m|h)');

const Map<String, double> _unitMicroseconds = {
  'ns': 0.001,
  'us': 1,
  'µs': 1,
  'μs': 1,
  'ms': 1000,
  's': 1000000,
  'm': 60000000,
  'h': 3600000000,
};

/// Parses a Go `time.ParseDuration` string. Returns null if [input] is not a
/// valid, non-negative Go duration (a bare number without unit is invalid,
/// except for "0").
Duration? tryParseGoDuration(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed == "0") return Duration.zero;

  double microseconds = 0;
  String rest = trimmed;
  while (rest.isNotEmpty) {
    final match = _segment.firstMatch(rest);
    if (match == null) return null;
    final value = double.parse(match.group(1)!);
    microseconds += value * _unitMicroseconds[match.group(2)!]!;
    rest = rest.substring(match.end);
  }
  return Duration(microseconds: microseconds.round());
}

/// Formats [duration] as a Go duration string in whole seconds, e.g. "28800s".
String formatGoDuration(Duration duration) => '${duration.inSeconds}s';
