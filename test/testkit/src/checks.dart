// Probe Test Kit: reading a value out of a state map and comparing it.
// Pure Dart.

/// The value at [path] ("game.hud.bestLine") in [state]. [found] tells a
/// missing part from a real null.
({Object? value, bool found}) lookup(Map<String, Object?> state, String path) {
  Object? cur = state;
  for (final part in path.split('.')) {
    if (cur is Map && cur.containsKey(part)) {
      cur = cur[part];
    } else {
      return (value: null, found: false);
    }
  }
  return (value: cur, found: true);
}

/// Result of one comparison: whether it holds and a plain-words description.
class CheckResult {
  const CheckResult(this.ok, this.message);
  final bool ok;
  final String message;
}

const Set<String> _ops = {
  'eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'contains', 'exists', 'in'
};

/// Compares the value at `args['path']` in [state] with the single
/// comparison word found in [args] (eq, ne, gt, gte, lt, lte, contains,
/// exists, in).
CheckResult evaluate(Map<String, Object?> state, Map<String, Object?> args) {
  final path = args['path']! as String;
  final got = lookup(state, path);
  final op = args.keys.firstWhere(_ops.contains);
  final want = args[op];
  final shown = got.found ? _show(got.value) : '(missing)';

  if (op == 'exists') {
    final wantPresent = want! as bool;
    return CheckResult(got.found == wantPresent,
        '$path ${wantPresent ? 'exists' : 'is absent'}; found $shown');
  }
  if (!got.found) {
    return CheckResult(
        false, '$path is not in the state (wanted $op ${_show(want)})');
  }
  final v = got.value;
  final bool ok;
  switch (op) {
    case 'eq':
      ok = v == want;
    case 'ne':
      ok = v != want;
    case 'in':
      ok = (want! as List).any((e) => v == e);
    case 'contains':
      ok = v is String && v.contains(want! as String);
    default:
      ok = v is num && _order(v, op, want! as num);
  }
  return CheckResult(ok, '$path $op ${_show(want)}; found $shown');
}

bool _order(num v, String op, num w) => switch (op) {
      'gt' => v > w,
      'gte' => v >= w,
      'lt' => v < w,
      _ => v <= w,
    };

String _show(Object? v) => v is String ? '"$v"' : '$v';
