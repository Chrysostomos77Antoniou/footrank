import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/models/team_model.dart';

void main() {
  group('canonicalCity', () {
    test('maps any case to the canonical list entry', () {
      expect(canonicalCity('nicosia'), 'Nicosia');
      expect(canonicalCity('  LIMASSOL '), 'Limassol');
      expect(canonicalCity('Paphos'), 'Paphos');
    });

    test('returns null for unknown or null', () {
      expect(canonicalCity('Athens'), isNull);
      expect(canonicalCity(null), isNull);
      expect(canonicalCity(''), isNull);
    });
  });

  group('TeamModel.record', () {
    TeamModel team({int w = 0, int l = 0, int d = 0}) => TeamModel(
          id: 't',
          name: 'T',
          captainId: 'c',
          wins: w,
          losses: l,
          draws: d,
          createdAt: DateTime(2026),
        );

    test('formats W and L', () {
      expect(team(w: 5, l: 2).record, '5W · 2L');
    });

    test('includes draws only when present', () {
      expect(team(w: 3, l: 1, d: 2).record, '3W · 1L · 2D');
      expect(team(w: 0, l: 0).record, '0W · 0L');
    });

    test('played counts all results', () {
      expect(team(w: 3, l: 1, d: 2).played, 6);
    });
  });
}
