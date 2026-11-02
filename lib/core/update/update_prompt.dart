import 'package:flutter/foundation.dart';
import 'package:footrank/services/supabase_service.dart';

/// The single row of `app_update_prompt`: the switch the owner flips (from the
/// admin panel, or by asking) to show every user on an older build a small
/// window, which cannot be closed, that sends them to their own store.
@immutable
class UpdatePromptConfig {
  final bool enabled;

  /// The newest version in the stores, e.g. `1.1.8`. Only people on a lower
  /// version see the window, so someone who already updated is never asked.
  final String latestVersion;
  final String iosUrl;
  final String androidUrl;

  const UpdatePromptConfig({
    required this.enabled,
    required this.latestVersion,
    required this.iosUrl,
    required this.androidUrl,
  });

  factory UpdatePromptConfig.fromJson(Map<String, dynamic> json) =>
      UpdatePromptConfig(
        enabled: json['enabled'] == true,
        latestVersion: ((json['latest_version'] as String?) ?? '').trim(),
        iosUrl: ((json['ios_url'] as String?) ?? '').trim(),
        androidUrl: ((json['android_url'] as String?) ?? '').trim(),
      );
}

/// Where a build runs, as far as the stores are concerned.
enum StorePlatform { ios, android }

/// Only iPhones go to the App Store and only Android phones go to Google Play;
/// any other platform (web, desktop) gets no update window at all.
StorePlatform? storePlatformFor(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS => StorePlatform.ios,
  TargetPlatform.android => StorePlatform.android,
  _ => null,
};

final RegExp _versionPattern = RegExp(r'^\d+(\.\d+){1,2}$');

/// `1.1.8` or `1.1` -- what the admin panel accepts as "the newest version".
bool isValidVersion(String value) => _versionPattern.hasMatch(value.trim());

List<int>? _parts(String version) {
  final core = version.split('+').first.trim();
  if (!_versionPattern.hasMatch(core)) return null;
  return core.split('.').map(int.parse).toList();
}

/// Whether [current] is a lower version than [latest]. The build number after
/// `+` is ignored. If either side does not parse, the answer is false: a typo
/// in the setting must never lock anybody out.
bool isOlderVersion(String current, String latest) {
  final a = _parts(current);
  final b = _parts(latest);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x < y;
  }
  return false;
}

/// A store link as a [Uri]; adds `https://` when it was typed without one.
/// Null when there is nothing usable.
Uri? normalizeStoreUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final withScheme = text.contains('://') ? text : 'https://$text';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || uri.host.isEmpty) return null;
  return uri;
}

/// The links to try, in order, for [platform]. iPhone: the App Store page.
/// Android: the Play Store app directly (`market://`), then the web page.
List<Uri> storeUrisFor(UpdatePromptConfig config, StorePlatform platform) {
  switch (platform) {
    case StorePlatform.ios:
      final uri = normalizeStoreUrl(config.iosUrl);
      return uri == null ? const [] : [uri];
    case StorePlatform.android:
      final web = normalizeStoreUrl(config.androidUrl);
      if (web == null) return const [];
      final id = web.queryParameters['id'];
      final isPlay = web.host.endsWith('play.google.com');
      return [
        if (isPlay && id != null && id.isNotEmpty)
          Uri(scheme: 'market', host: 'details', queryParameters: {'id': id}),
        web,
      ];
  }
}

class UpdatePromptRepository {
  /// Null when the row is missing. Throws on network errors; the caller treats
  /// that as "no window".
  Future<UpdatePromptConfig?> fetch() async {
    final row = await SupabaseService.client
        .from('app_update_prompt')
        .select()
        .maybeSingle()
        .timeout(const Duration(seconds: 6));
    return row == null ? null : UpdatePromptConfig.fromJson(row);
  }
}
