import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:footrank/services/supabase_service.dart';

/// True while a password-recovery deep link is being handled. The router watches
/// this to force the user onto the "set a new password" screen (and keep them
/// there) before they can enter the app.
final passwordRecovery = ValueNotifier<bool>(false);

/// Attach once at startup: flips [passwordRecovery] on when Supabase reports the
/// recovery deep link arrived, and off when the user signs out.
void initPasswordRecoveryListener() {
  SupabaseService.client.auth.onAuthStateChange.listen((state) {
    switch (state.event) {
      case AuthChangeEvent.passwordRecovery:
        passwordRecovery.value = true;
        break;
      case AuthChangeEvent.signedOut:
        passwordRecovery.value = false;
        break;
      default:
        break;
    }
  });
}
