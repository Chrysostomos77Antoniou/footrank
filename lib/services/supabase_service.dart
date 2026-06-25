import 'package:http/http.dart' show Client;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:footrank/core/constants/app_constants.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  /// Initializes Supabase. Pass [httpClient] in tests to mock the backend
  /// (no network). Production passes nothing, so behavior is unchanged.
  static Future<void> initialize({Client? httpClient}) async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
      httpClient: httpClient,
    );
  }
}
