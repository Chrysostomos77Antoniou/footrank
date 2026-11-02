import 'package:flutter/material.dart';
import 'package:footrank/admin/data/admin_repository.dart';
import 'package:footrank/admin/presentation/widgets/admin_widgets.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/update/update_prompt.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/feedback.dart';

/// The "new version" window's switch. When on, everyone whose app is older
/// than the version typed here sees a window they cannot close, with one
/// button to their own store (App Store on iPhone, Google Play on Android).
class AdminUpdatePage extends StatefulWidget {
  /// Injected in widget tests; production uses the real repository.
  final AdminRepository? repo;

  const AdminUpdatePage({super.key, this.repo});

  @override
  State<AdminUpdatePage> createState() => _AdminUpdatePageState();
}

class _AdminUpdatePageState extends State<AdminUpdatePage> {
  late final AdminRepository _repo = widget.repo ?? AdminRepository();
  final _version = TextEditingController();

  UpdatePromptConfig? _saved;
  Object? _error;
  bool _enabled = false;
  bool _busy = false;
  String? _versionError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _version.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await _repo.fetchUpdatePrompt();
      if (!mounted) return;
      setState(() {
        _saved = config;
        _error = null;
        _enabled = config?.enabled ?? false;
        _version.text = config?.latestVersion ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  bool get _changed {
    final saved = _saved;
    if (saved == null) return false;
    return _enabled != saved.enabled ||
        _version.text.trim() != saved.latestVersion;
  }

  Future<void> _save() async {
    final version = _version.text.trim();
    if (version.isNotEmpty && !isValidVersion(version)) {
      setState(() => _versionError = 'Use a version like 1.1.8');
      return;
    }
    if (_enabled && version.isEmpty) {
      setState(() => _versionError = 'Enter the newest version first');
      return;
    }
    setState(() {
      _versionError = null;
      _busy = true;
    });
    try {
      await _repo.setUpdatePrompt(enabled: _enabled, latestVersion: version);
      if (!mounted) return;
      showSuccess(
        context,
        _enabled ? 'The update window is ON' : 'The update window is OFF',
      );
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.muted(context);
    final saved = _saved;
    final Widget body;
    if (saved != null) {
      body = ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      key: const Key('update-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show the update window'),
                      subtitle: Text(
                        _enabled
                            ? 'ON: users on an older version see it every time '
                                'they open the app.'
                            : 'OFF: nobody sees it.',
                      ),
                      value: _enabled,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                _enabled = v;
                                _versionError = null;
                              }),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      key: const Key('update-version'),
                      controller: _version,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _versionError = null),
                      decoration: InputDecoration(
                        labelText: 'Newest version in the stores',
                        hintText: '1.1.8',
                        helperText: 'Only apps older than this see the window.',
                        errorText: _versionError,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        key: const Key('update-save'),
                        onPressed: _busy || !_changed ? null : _save,
                        child: Text(_busy ? 'Saving...' : 'Save'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'The button sends iPhone users to the App Store and '
                      'Android users to Google Play, never the other way round.',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SelectableText(
                      'App Store: ${saved.iosUrl}\nGoogle Play: ${saved.androidUrl}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    } else if (_error != null) {
      body = Align(
        alignment: Alignment.topCenter,
        child: AdminEmptyState(
          icon: Icons.error_outline,
          message: friendlyError(_error!),
          actionLabel: 'Try again',
          onAction: () {
            setState(() => _error = null);
            _load();
          },
        ),
      );
    } else {
      body = const AdminTableSkeleton(rows: 3);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminHeader(
          title: 'App update',
          subtitle:
              'Ask users on an older version to update. Off by default; '
              'switch it on after the new version is live in both stores.',
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(child: body),
      ],
    );
  }
}
