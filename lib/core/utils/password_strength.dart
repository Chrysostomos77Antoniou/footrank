/// Validates password strength, matching the strongest character-class
/// option Supabase Auth itself offers (Authentication > Policies > Password
/// Requirements): min 8 chars, at least one digit, one lowercase letter,
/// one uppercase letter, and one symbol. Returns an error message, or null
/// if the password passes.
String? passwordStrengthError(String? value) {
  if (value == null || value.length < 8) {
    return 'Use at least 8 characters';
  }
  if (!RegExp(r'[0-9]').hasMatch(value)) {
    return 'Add at least one number';
  }
  if (!RegExp(r'[a-z]').hasMatch(value)) {
    return 'Add at least one lowercase letter';
  }
  if (!RegExp(r'[A-Z]').hasMatch(value)) {
    return 'Add at least one uppercase letter';
  }
  if (!RegExp(r'''[!@#$%^&*()_+\-=\[\]{};:'"|<>?,./~]''').hasMatch(value)) {
    return 'Add at least one symbol (e.g. ! @ # \$ %)';
  }
  return null;
}
