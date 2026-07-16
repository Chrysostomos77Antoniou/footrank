import 'package:supabase_flutter/supabase_flutter.dart';

/// Converts an exception into a concise, user-friendly message.
String friendlyError(Object error) {
  // Supabase's own .message is already clean, human-readable text (e.g.
  // "Invalid login credentials") -- error.toString() instead dumps the raw
  // "AuthApiException(message: ..., statusCode: ..., code: ...)" wrapper,
  // which is what every auth screen was actually showing users.
  if (error is AuthException) return error.message;

  var msg = error.toString();

  // Strip common Dart/Supabase prefixes.
  msg = msg
      .replaceFirst('Exception: ', '')
      .replaceFirst('StateError: ', '')
      .replaceFirst('PostgrestException(message: ', '');

  final lower = msg.toLowerCase();
  if (lower.contains('teams_name_lower_unique')) {
    return 'A team with that name already exists. Please pick another name.';
  }
  if (lower.contains('duplicate') || lower.contains('unique')) {
    return 'That already exists.';
  }
  if (lower.contains('network') ||
      lower.contains('socket') ||
      lower.contains('failed host lookup')) {
    return 'Network error. Check your connection.';
  }
  if (lower.contains('jwt') || lower.contains('not authenticated')) {
    return 'Your session expired. Please sign in again.';
  }

  // Trim overly long technical messages.
  if (msg.length > 140) msg = '${msg.substring(0, 137)}...';
  return msg;
}
