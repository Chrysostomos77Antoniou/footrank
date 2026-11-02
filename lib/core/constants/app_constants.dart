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
}
