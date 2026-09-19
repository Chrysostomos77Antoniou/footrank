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
  if (lower.contains('rating_gap_too_large')) {
    // Server message looks like "rating_gap_too_large: 2100 vs 1500 (max 200
    // right now)" -- pull the numbers out for a specific, useful message,
    // but degrade to a generic one if the format ever changes server-side.
    final match =
        RegExp(r'rating_gap_too_large:\s*(\d+)\s*vs\s*(\d+)\s*\(max\s*(\d+)')
            .firstMatch(msg);
    if (match != null) {
      final gap =
          (int.parse(match.group(1)!) - int.parse(match.group(2)!)).abs();
      final limit = match.group(3);
      return 'This team\'s Pitch Power is too far from yours right now '
          '($gap points apart, limit is $limit). This opens up automatically '
          'closer to kick-off, or try a more evenly matched team.';
    }
    return 'This team\'s Pitch Power is too far from yours right now. This '
        'opens up automatically closer to kick-off, or try a more evenly '
        'matched team.';
  }
  if (lower.contains('pwr_assessment_required')) {
    return "Finish your Pitch Power quiz before creating or joining a team.";
  }
  if (lower.contains('assessment_already_completed')) {
    return "You've already completed the Pitch Power quiz.";
  }
  if (lower.contains('incomplete_assessment')) {
    return 'Please answer every question before continuing.';
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
