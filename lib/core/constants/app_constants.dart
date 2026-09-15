class AppConstants {
  static const String appName = 'FootRank';

  // Supabase config is injected at build time via --dart-define so secrets are
  // never committed to git. For release builds pass them explicitly, e.g.:
  //   flutter build apk --release \
  //     --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  //     --dart-define=SUPABASE_ANON_KEY=<anon-key>
  // Store the real values in CI secrets (GitHub Actions -> Settings -> Secrets).
  //
  // The defaults below are NON-SECRET placeholders. They only exist so the
  // app/tests compile and run when no --dart-define is provided (integration
  // tests use a mock HTTP client, so the real backend is never contacted). They
  // must never be replaced with real project values.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://localhost.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'public-anon-key',
  );

  /// Stripe PUBLISHABLE key (pk_...), injected the same way as the Supabase
  /// config above:
  ///   --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_...
  ///
  /// A publishable key is designed to ship in a client and is not a secret, but
  /// it is still build-time config rather than a committed constant so test and
  /// live builds can't be mixed up.
  ///
  /// The SECRET key (sk_...) must NEVER appear in this app — it lives only in
  /// the Supabase Edge Function secrets, which is what actually creates charges.
  ///
  /// Empty by default, which disables the payment UI entirely (see
  /// PaymentRepository.isEnabled) rather than showing a button that can only
  /// fail. That keeps `flutter run` and the test suite working with no Stripe
  /// account at all.
  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: '',
  );
}
