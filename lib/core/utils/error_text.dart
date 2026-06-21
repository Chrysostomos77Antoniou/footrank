/// Converts an exception into a concise, user-friendly message.
String friendlyError(Object error) {
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
