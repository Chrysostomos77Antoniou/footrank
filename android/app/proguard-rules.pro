# R8 keep rules for FootRank release builds.
# Flutter's own engine/plugin classes are covered by the consumer rules each
# plugin AAR ships, so this file only covers the reflection/JNI-heavy SDKs
# that have historically needed explicit help.

# Flutter's Play Core deferred-component references trip R8's "missing
# class" check even when split install isn't used -- the standard workaround.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Facebook Android SDK (flutter_facebook_auth) -- official rules from
# Facebook's own Android SDK docs.
-keep class com.facebook.** { *; }
-keep class com.facebook.internal.** { *; }
-dontwarn com.facebook.**

# Google Play Services / Google Sign-In.
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# flutter_local_notifications serializes scheduled-notification data with
# Gson; keep its model classes so field names survive.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Firebase Crashlytics -- keep stack traces readable/symbolicated.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# video_player (ExoPlayer/Media3) -- optional codec extensions we don't ship.
-dontwarn com.google.android.exoplayer2.**

# flutter_stripe wraps Stripe's React Native SDK, whose push-provisioning proxy
# references com.stripe.android.pushProvisioning.*. Those classes live in the
# separate stripe-android-issuing-push-provisioning artifact, which we don't
# depend on: push provisioning is for adding issued cards to a device wallet,
# and FootRank only ever takes a card payment. R8 still fails on the dangling
# references, exactly like the Play Core case above.
-dontwarn com.stripe.android.pushProvisioning.**
-keep class com.stripe.android.pushProvisioning.** { *; }
