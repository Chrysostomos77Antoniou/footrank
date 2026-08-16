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
  if (lower.contains('phone_taken') ||
      lower.contains('uq_user_contacts_phone_normalized')) {
    return 'That phone number is already linked to another account.';
  }
  if (lower.contains('phone_invalid')) {
    return 'Enter a valid Cyprus mobile, e.g. 99 123456.';
  }
  if (lower.contains('phone_required')) {
    return 'Phone number is required.';
  }
  if (lower.contains('attendance_required')) {
    return 'Mark at least 5 attended players for your team before submitting a score.';
  }
  if (lower.contains('teams_name_lower_unique')) {
    return 'A team with that name already exists. Please pick another name.';
  }
  if (lower.contains('uniq_pending_request')) {
    return 'You already have a pending request for this team.';
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
