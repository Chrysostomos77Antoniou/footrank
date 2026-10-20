import 'package:flutter_test/flutter_test.dart';
import 'package:footrank/core/utils/text_utils.dart';

void main() {
  test('firstChar keeps whole emoji / flags', () {
    expect(firstChar('🇧🇷'), '🇧🇷');
    expect(firstChar('⚽ Team'), '⚽');
    expect(firstChar('  bob'), 'B');
    expect(firstChar(''), '?');
    expect(firstChar('', fallback: 'F'), 'F');
  });

  test('firstChars never splits a character', () {
    expect(firstChars('🇧🇷🇨🇾x', 2), '🇧🇷🇨🇾');
    expect(firstChars('ab', 2), 'AB');
  });

  test('truncate cuts on whole characters', () {
    expect(truncate('abcdef', 5), 'ab...');
    final s = '😀' * 10;
    expect(truncate(s, 5), '😀😀...');
    expect(truncate('short', 10), 'short');
  });
}
