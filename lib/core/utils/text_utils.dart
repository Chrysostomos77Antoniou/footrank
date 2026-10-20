import 'package:characters/characters.dart';

/// Safe text helpers. Never index a Dart string with `s[0]` / `substring` to
/// get "the first letter": strings are UTF-16, so an emoji (a flag, a face, an
/// accented letter written as base + mark) is split in half and Flutter then
/// crashes drawing it ("string is not well-formed UTF-16"). These work on
/// whole user-perceived characters (grapheme clusters) instead.

/// The first whole character of [s], upper-cased, or [fallback] if empty.
String firstChar(String s, {String fallback = '?'}) {
  final t = s.trim();
  if (t.isEmpty) return fallback;
  return t.characters.first.toUpperCase();
}

/// Up to the first [count] whole characters of [s], upper-cased.
String firstChars(String s, int count) {
  return s.trim().characters.take(count).toString().toUpperCase();
}

/// [s] shortened to at most [max] whole characters, with "..." when cut.
String truncate(String s, int max) {
  final c = s.characters;
  if (c.length <= max) return s;
  return '${c.take(max - 3)}...';
}
