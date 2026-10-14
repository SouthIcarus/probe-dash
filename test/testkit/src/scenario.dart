// Probe Test Kit: the scenario file format, parsed and checked strictly.
// Pure Dart (no Flutter), so the rules are unit-tested on their own.
import 'dart:convert';

/// A scenario file that cannot be used. The message names the file, the step
/// and what to change, in plain words.
class ScenarioError implements Exception {
  ScenarioError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Largest scenario file accepted (anything a user can load is size-checked).
const int maxScenarioBytes = 64 * 1024;
const int maxSteps = 200;
const int maxAdvanceMs = 120000;

/// The comparison words a condition may use (exactly one per condition).
const List<String> comparisons = [
  'eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'contains', 'exists', 'in'
];

const Map<String, Set<String>> _stepKeys = {
  'tap': {'text', 'times'},
  'tap_at': {'x', 'y'},
  'back': {},
  'advance': {'ms'},
  'wait_state': {'path', 'timeoutMs', ...comparisons},
  'expect': {'path', 'why', ...comparisons},
  'expect_text': {'text', 'count'},
  'shot': {'name'},
  'set_profile': {'size', 'dpr', 'topInsetPx', 'fontScale'},
};

/// Step names that mean "wait a fixed time": refused with a hint.
const Set<String> _sleepWords = {'sleep', 'wait', 'delay', 'pause', 'wait_ms'};

class Profile {
  const Profile({
    this.width = 411,
    this.height = 891,
    this.dpr = 2.63,
    this.topInsetPx = 0,
    this.fontScale = 1.0,
    this.seed = 1,
  });

  /// Logical size in dp.
  final double width, height;
  final double dpr;

  /// Top system inset (camera hole) in physical pixels.
  final double topInsetPx;
  final double fontScale;
  final int seed;

  Map<String, Object?> toJson() => {
        'size': [width, height],
        'dpr': dpr,
        'topInsetPx': topInsetPx,
        'fontScale': fontScale,
        'seed': seed,
      };
}

class Setup {
  const Setup({
    this.saveFixture,
    this.saveInline,
    this.rewardedReady = true,
    this.rewardedWatchResult = false,
  });

  /// Path under `testkit/` of a save fixture, or an inline save object.
  final String? saveFixture;
  final Map<String, Object?>? saveInline;
  final bool rewardedReady;
  final bool rewardedWatchResult;
}

class Step {
  const Step(this.index, this.op, this.args);
  final int index; // 1-based, for messages
  final String op;
  final Map<String, Object?> args;

  /// Steps that carry a check on the game or the screen.
  bool get isAssertion => op == 'expect' || op == 'expect_text';
}

class Scenario {
  const Scenario({
    required this.id,
    required this.title,
    required this.covers,
    required this.profile,
    required this.setup,
    required this.steps,
    required this.canary,
    required this.sha256,
  });

  final String id;
  final String title;
  final List<String> covers;
  final Profile profile;
  final Setup setup;
  final List<Step> steps;

  /// A canary must PASS on a good build and FAIL with the fault switched on.
  final bool canary;

  /// Hash of the file text (line endings normalised), for the manifest.
  final String sha256;

  int get assertionCount => steps.where((s) => s.isAssertion).length;
}

final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9-]{2,60}$');
final RegExp _coverPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]{0,40}$');

/// Parses [text] (the content of `<fileId>.json`). Throws [ScenarioError].
Scenario parseScenario(String fileId, String text, {required String sha256}) {
  String where([int? step]) =>
      step == null ? 'Scenario "$fileId"' : 'Scenario "$fileId", step $step';

  if (utf8.encode(text).length > maxScenarioBytes) {
    throw ScenarioError('${where()}: file is larger than $maxScenarioBytes '
        'bytes. Split it into smaller scenarios.');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    throw ScenarioError('${where()}: not valid JSON (${e.message}).');
  }
  if (decoded is! Map<String, Object?>) {
    throw ScenarioError('${where()}: the file must be one JSON object.');
  }
  const topKeys = {
    'id', 'title', 'covers', 'canary', 'profile', 'setup', 'steps'
  };
  for (final k in decoded.keys) {
    if (!topKeys.contains(k)) {
      throw ScenarioError('${where()}: unknown field "$k". '
          'Allowed: ${topKeys.join(', ')}.');
    }
  }
  final id = decoded['id'];
  if (id is! String || !_idPattern.hasMatch(id)) {
    throw ScenarioError('${where()}: "id" must be lowercase letters, digits '
        'and dashes, 3 to 61 characters.');
  }
  if (id != fileId) {
    throw ScenarioError('${where()}: "id" is "$id" but the file is named '
        '"$fileId.json". They must match.');
  }
  final title = decoded['title'];
  if (title is! String || title.trim().isEmpty || title.length > 140) {
    throw ScenarioError('${where()}: "title" must be a short sentence.');
  }
  final covers = decoded['covers'];
  if (covers is! List ||
      covers.isEmpty ||
      covers.any((c) => c is! String || !_coverPattern.hasMatch(c))) {
    throw ScenarioError('${where()}: "covers" must list at least one '
        'requirement ID, for example ["A-20"].');
  }
  final canary = decoded['canary'] ?? false;
  if (canary is! bool) {
    throw ScenarioError('${where()}: "canary" must be true or false.');
  }

  final profile = _parseProfile(decoded['profile'], where());
  final setup = _parseSetup(decoded['setup'], where());

  final rawSteps = decoded['steps'];
  if (rawSteps is! List || rawSteps.isEmpty) {
    throw ScenarioError('${where()}: "steps" must be a non-empty list.');
  }
  if (rawSteps.length > maxSteps) {
    throw ScenarioError('${where()}: more than $maxSteps steps. '
        'Split it into smaller scenarios.');
  }
  final steps = <Step>[];
  for (var i = 0; i < rawSteps.length; i++) {
    steps.add(_parseStep(i + 1, rawSteps[i], where(i + 1)));
  }
  if (!steps.any((s) => s.isAssertion)) {
    throw ScenarioError('${where()}: no "expect" or "expect_text" step. '
        'A scenario that checks nothing cannot fail.');
  }
  return Scenario(
    id: id,
    title: title,
    covers: covers.cast<String>(),
    profile: profile,
    setup: setup,
    steps: steps,
    canary: canary,
    sha256: sha256,
  );
}

num _num(Object? v, String what, String where,
    {required num min, required num max}) {
  if (v is! num || v < min || v > max) {
    throw ScenarioError('$where: "$what" must be a number from $min to $max.');
  }
  return v;
}

Profile _parseProfile(Object? raw, String where) {
  if (raw == null) return const Profile();
  if (raw is! Map<String, Object?>) {
    throw ScenarioError('$where: "profile" must be an object.');
  }
  const allowed = {'size', 'dpr', 'topInsetPx', 'fontScale', 'seed'};
  for (final k in raw.keys) {
    if (!allowed.contains(k)) {
      throw ScenarioError('$where: unknown profile field "$k". '
          'Allowed: ${allowed.join(', ')}.');
    }
  }
  final size = raw['size'];
  var w = 411.0, h = 891.0;
  if (size != null) {
    if (size is! List || size.length != 2) {
      throw ScenarioError('$where: profile "size" must be [width, height].');
    }
    w = _num(size[0], 'size width', where, min: 200, max: 2000).toDouble();
    h = _num(size[1], 'size height', where, min: 200, max: 3000).toDouble();
  }
  final seed = raw['seed'];
  if (seed != null && seed is! int) {
    throw ScenarioError('$where: profile "seed" must be a whole number.');
  }
  return Profile(
    width: w,
    height: h,
    dpr: raw['dpr'] == null
        ? 2.63
        : _num(raw['dpr'], 'dpr', where, min: 0.5, max: 6).toDouble(),
    topInsetPx: raw['topInsetPx'] == null
        ? 0
        : _num(raw['topInsetPx'], 'topInsetPx', where, min: 0, max: 600)
            .toDouble(),
    fontScale: raw['fontScale'] == null
        ? 1.0
        : _num(raw['fontScale'], 'fontScale', where, min: 0.5, max: 3)
            .toDouble(),
    seed: (seed as int?) ?? 1,
  );
}

Setup _parseSetup(Object? raw, String where) {
  if (raw == null) return const Setup();
  if (raw is! Map<String, Object?>) {
    throw ScenarioError('$where: "setup" must be an object.');
  }
  const allowed = {'save', 'ads'};
  for (final k in raw.keys) {
    if (!allowed.contains(k)) {
      throw ScenarioError('$where: unknown setup field "$k". '
          'Allowed: ${allowed.join(', ')}.');
    }
  }
  String? fixture;
  Map<String, Object?>? inline;
  final save = raw['save'];
  if (save is String) {
    if (!RegExp(r'^fixtures/[a-z0-9-]+\.json$').hasMatch(save)) {
      throw ScenarioError('$where: setup "save" must look like '
          '"fixtures/fresh.json" (a file in testkit/fixtures/).');
    }
    fixture = save;
  } else if (save is Map<String, Object?>) {
    inline = save;
  } else if (save != null) {
    throw ScenarioError(
        '$where: setup "save" must be a fixture path or an object.');
  }
  var ready = true, watch = false;
  final ads = raw['ads'];
  if (ads != null) {
    if (ads is! Map<String, Object?>) {
      throw ScenarioError('$where: setup "ads" must be an object.');
    }
    for (final k in ads.keys) {
      if (k != 'rewardedReady' && k != 'rewardedWatchResult') {
        throw ScenarioError('$where: unknown ads field "$k". Allowed: '
            'rewardedReady, rewardedWatchResult.');
      }
    }
    final r = ads['rewardedReady'] ?? true;
    final w = ads['rewardedWatchResult'] ?? false;
    if (r is! bool || w is! bool) {
      throw ScenarioError('$where: ads fields must be true or false.');
    }
    ready = r;
    watch = w;
  }
  return Setup(
    saveFixture: fixture,
    saveInline: inline,
    rewardedReady: ready,
    rewardedWatchResult: watch,
  );
}

Step _parseStep(int index, Object? raw, String where) {
  if (raw is! Map<String, Object?>) {
    throw ScenarioError('$where: a step must be an object like '
        '{"do": "tap", "text": "PLAY"}.');
  }
  final op = raw['do'];
  if (op is! String) {
    throw ScenarioError('$where: missing "do". Allowed steps: '
        '${_stepKeys.keys.join(', ')}.');
  }
  if (_sleepWords.contains(op)) {
    throw ScenarioError('$where: "$op" is not allowed: no fixed sleeps. '
        'Use {"do": "wait_state", "path": ..., "eq": ..., "timeoutMs": ...} '
        'to wait for something, or "advance" to move the game clock.');
  }
  final allowed = _stepKeys[op];
  if (allowed == null) {
    throw ScenarioError('$where: unknown step "$op". Allowed steps: '
        '${_stepKeys.keys.join(', ')}.');
  }
  final args = <String, Object?>{};
  for (final e in raw.entries) {
    if (e.key == 'do') continue;
    if (!allowed.contains(e.key)) {
      throw ScenarioError('$where: step "$op" has no field "${e.key}". '
          'Allowed: ${allowed.isEmpty ? '(none)' : allowed.join(', ')}.');
    }
    args[e.key] = e.value;
  }
  void need(String key, bool Function(Object?) ok, String hint) {
    if (!args.containsKey(key) || !ok(args[key])) {
      throw ScenarioError('$where: step "$op" needs "$key" $hint.');
    }
  }

  bool isText(Object? v) => v is String && v.isNotEmpty && v.length <= 80;
  bool isFraction(Object? v) => v is num && v >= 0 && v <= 1;

  switch (op) {
    case 'tap':
      need('text', isText, '(the exact words on the button)');
      final t = args['times'] ?? 1;
      if (t is! int || t < 1 || t > 5) {
        throw ScenarioError(
            '$where: "times" must be a whole number 1 to 5 (taps inside '
            'one frame).');
      }
    case 'tap_at':
      need('x', isFraction, 'as a fraction of the width, 0 to 1');
      need('y', isFraction, 'as a fraction of the height, 0 to 1');
    case 'advance':
      need('ms', (v) => v is int && v >= 1 && v <= maxAdvanceMs,
          'as whole milliseconds from 1 to $maxAdvanceMs');
    case 'expect_text':
      need('text', isText, '(the exact words to look for)');
      final c = args['count'] ?? 1;
      if (c is! int || c < 0 || c > 20) {
        throw ScenarioError('$where: "count" must be a whole number 0 to 20.');
      }
    case 'shot':
      need(
          'name',
          (v) => v is String && RegExp(r'^[a-z0-9-]{1,40}$').hasMatch(v),
          '(lowercase letters, digits, dashes)');
    case 'set_profile':
      if (args.isEmpty) {
        throw ScenarioError('$where: "set_profile" needs at least one of '
            'size, dpr, topInsetPx, fontScale.');
      }
      _parseProfile(Map<String, Object?>.of(args), where);
    case 'wait_state':
    case 'expect':
      need(
          'path',
          (v) => v is String && RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(v),
          '(a state path like "game.phase")');
      final used = args.keys.where(comparisons.contains).toList();
      if (used.length != 1) {
        throw ScenarioError('$where: step "$op" needs exactly one of '
            '${comparisons.join(', ')} (found ${used.length}).');
      }
      if (op == 'wait_state') {
        need('timeoutMs', (v) => v is int && v >= 100 && v <= maxAdvanceMs,
            'as whole milliseconds from 100 to $maxAdvanceMs');
      }
      final word = used.first;
      if (word == 'in' && args['in'] is! List) {
        throw ScenarioError('$where: "in" needs a list.');
      }
      if (word == 'exists' && args['exists'] is! bool) {
        throw ScenarioError('$where: "exists" needs true or false.');
      }
      if (const {'gt', 'gte', 'lt', 'lte'}.contains(word) &&
          args[word] is! num) {
        throw ScenarioError('$where: "$word" needs a number.');
      }
      if (word == 'contains' && args['contains'] is! String) {
        throw ScenarioError('$where: "contains" needs text.');
      }
  }
  return Step(index, op, args);
}
