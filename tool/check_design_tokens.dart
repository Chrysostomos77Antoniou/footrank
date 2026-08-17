// Design-token enforcement gate.
//
// WHY A RATCHET, NOT A HARD LINT
// ------------------------------
// The codebase currently carries hundreds of pre-token violations (222 magic
// spacers, 41 off-scale radii, 80 raw font sizes at the time of writing).
// Turning on a rule that fails on all of them would leave the analyzer
// permanently red and the gate permanently ignored — the failure mode every
// lint-adoption post-mortem describes.
//
// So this counts violations per category and compares against a committed
// baseline. New violations fail the build; existing ones are tracked and burn
// down as screens migrate. The baseline may only ever go down: `--update`
// refuses to raise it.
//
// Usage:
//   dart run tool/check_design_tokens.dart            # check (CI)
//   dart run tool/check_design_tokens.dart --update   # lower the baseline
//   dart run tool/check_design_tokens.dart --list rawFontSize
//
// The token layer itself is exempt — it is where these values are *supposed*
// to be defined.

import 'dart:convert';
import 'dart:io';

const _baselinePath = 'tool/design_token_baseline.json';

/// Files allowed to contain raw design values: the token layer itself.
const _exemptPrefixes = <String>[
  'lib/core/theme/',
];

class Rule {
  final String id;
  final String description;
  final RegExp pattern;
  final String fix;

  const Rule(this.id, this.description, this.pattern, this.fix);
}

final _rules = <Rule>[
  Rule(
    'rawColor',
    'Hardcoded colour literal',
    RegExp(r'Color\(0x'),
    'Add it to AppColors and reference that instead.',
  ),
  Rule(
    'rawRadius',
    'Hardcoded corner radius',
    RegExp(r'BorderRadius\.circular\(\s*\d'),
    'Use AppSemantic.cardRadius / controlRadius / chipRadius / pill.',
  ),
  Rule(
    'rawFontSize',
    'Hardcoded font size',
    RegExp(r'fontSize:\s*\d'),
    'Use a Theme.of(context).textTheme role, or AppTypeScale.',
  ),
  Rule(
    'rawDuration',
    'Hardcoded animation duration',
    RegExp(r'Duration\(\s*milliseconds:\s*\d'),
    'Use AppMotion.press / quick / enter.',
  ),
  Rule(
    'magicSpacer',
    'SizedBox with a magic number',
    RegExp(r'SizedBox\(\s*(height|width):\s*\d'),
    'Use AppSpacing.* or AppSemantic.rowGap / sectionGap.',
  ),
];

bool _isExempt(String path) {
  final norm = path.replaceAll(r'\', '/');
  return _exemptPrefixes.any(norm.contains);
}

/// Strips `//` line comments so a rule name mentioned in a doc comment does not
/// count as a violation. Deliberately naive — it does not handle `/* */` or a
/// `//` inside a string literal. Both are rare enough here that the extra
/// machinery would cost more than it saves.
String _stripComment(String line) {
  final t = line.trimLeft();
  if (t.startsWith('//')) return '';
  return line;
}

class Violation {
  final String file;
  final int line;
  final String text;
  Violation(this.file, this.line, this.text);
}

Map<String, List<Violation>> scan() {
  final results = <String, List<Violation>>{
    for (final r in _rules) r.id: <Violation>[],
  };

  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('lib/ not found — run from the project root.');
    exit(2);
  }

  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (_isExempt(path)) continue;

    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = _stripComment(lines[i]);
      if (line.isEmpty) continue;
      for (final rule in _rules) {
        if (rule.pattern.hasMatch(line)) {
          results[rule.id]!.add(Violation(path, i + 1, lines[i].trim()));
        }
      }
    }
  }
  return results;
}

bool get _baselineExists => File(_baselinePath).existsSync();

Map<String, int> _readBaseline() {
  final f = File(_baselinePath);
  if (!f.existsSync()) return {for (final r in _rules) r.id: 0};
  final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final counts = (raw['counts'] as Map<String, dynamic>?) ?? {};
  return {
    for (final r in _rules) r.id: (counts[r.id] as int?) ?? 0,
  };
}

void _writeBaseline(Map<String, int> counts) {
  final payload = const JsonEncoder.withIndent('  ').convert({
    'note': 'Design-token violation baseline. May only decrease. '
        'Regenerate with: dart run tool/check_design_tokens.dart --update',
    'counts': counts,
  });
  File(_baselinePath).writeAsStringSync('$payload\n');
}

void main(List<String> args) {
  final results = scan();
  final counts = {for (final e in results.entries) e.key: e.value.length};

  if (args.contains('--list')) {
    final idx = args.indexOf('--list');
    final which = idx + 1 < args.length ? args[idx + 1] : null;
    for (final rule in _rules) {
      if (which != null && rule.id != which) continue;
      final v = results[rule.id]!;
      stdout.writeln('\n${rule.id} — ${rule.description} (${v.length})');
      stdout.writeln('  fix: ${rule.fix}');
      for (final x in v) {
        stdout.writeln('  ${x.file}:${x.line}  ${x.text}');
      }
    }
    return;
  }

  final baseline = _readBaseline();

  if (args.contains('--update')) {
    // First run has nothing to ratchet against: record where we actually are.
    if (!_baselineExists) {
      _writeBaseline(counts);
      stdout.writeln('Initial baseline recorded:');
      counts.forEach((k, v) => stdout.writeln('  $k: $v'));
      return;
    }
    final next = <String, int>{};
    var raised = false;
    for (final r in _rules) {
      final now = counts[r.id]!;
      final was = baseline[r.id]!;
      if (now > was) {
        stderr.writeln(
            'Refusing to raise baseline for ${r.id}: $was -> $now. '
            'Fix the new violations instead.');
        raised = true;
      }
      next[r.id] = now < was ? now : was;
    }
    if (raised) exit(1);
    _writeBaseline(next);
    stdout.writeln('Baseline updated:');
    next.forEach((k, v) => stdout.writeln('  $k: $v'));
    return;
  }

  var failed = false;
  stdout.writeln('Design-token gate\n');
  for (final rule in _rules) {
    final now = counts[rule.id]!;
    final was = baseline[rule.id]!;
    final delta = now - was;
    final status = delta > 0
        ? 'FAIL  +$delta'
        : delta < 0
            ? 'ok    $delta (burned down — run --update)'
            : 'ok';
    stdout.writeln(
        '  ${rule.id.padRight(14)} $now (baseline $was)  $status');
    if (delta > 0) {
      failed = true;
      for (final v in results[rule.id]!.take(10)) {
        stdout.writeln('      ${v.file}:${v.line}  ${v.text}');
      }
      stdout.writeln('      fix: ${rule.fix}');
    }
  }

  if (failed) {
    stdout.writeln('\nNew design-token violations introduced. '
        'Use the token layer instead of raw values.');
    exit(1);
  }
  stdout.writeln('\nNo new violations.');
}
