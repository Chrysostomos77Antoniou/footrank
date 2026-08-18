import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/error_text.dart';

/// Transient feedback and destructive confirmation.
///
/// Replaces ~125 hand-built `SnackBar(content: Text(...))` calls that gave a
/// failed action and a confirmed one the exact same grey pill, and ~14
/// copy-pasted destructive dialogs whose labels and button order had drifted
/// apart screen by screen.
///
/// Design decisions worth knowing:
///
/// * **Icon + colour, never colour alone.** WCAG 2.2 SC 1.4.1 — an error must
///   not be signalled by hue only. Every variant carries a distinct icon.
/// * **Tinted surface, not a solid colour fill.** White-on-danger measures
///   ~3.4:1 and white-on-success ~2.5:1, both under the 4.5:1 floor for body
///   text. Painting the *icon* and a leading stripe in the semantic colour and
///   leaving the text on a normal surface keeps text contrast high while still
///   reading as success/failure at a glance. It also matches the app's
///   outlined-surface strategy ([AppElevation.flat]).
/// * **Longer dwell when there is something to do.** 4s normally, 6s when the
///   snackbar carries an action, since the user has to read *and* decide.

enum _Kind { success, error, info }

extension on _Kind {
  IconData get icon => switch (this) {
        _Kind.success => Icons.check_circle_outline,
        _Kind.error => Icons.error_outline,
        _Kind.info => Icons.info_outline,
      };

  Color color(BuildContext context) => switch (this) {
        _Kind.success => AppColors.success,
        _Kind.error => AppColors.danger,
        _Kind.info => AppColors.iconAccent(context),
      };

  String get semanticPrefix => switch (this) {
        _Kind.success => 'Success',
        _Kind.error => 'Error',
        _Kind.info => 'Information',
      };
}

void _show(
  BuildContext context,
  String message,
  _Kind kind, {
  SnackBarAction? action,
}) {
  final theme = Theme.of(context);
  final accent = kind.color(context);
  final messenger = ScaffoldMessenger.of(context);

  // One at a time — stacked snackbars queue up and the user reads a stale one.
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: theme.brightness == Brightness.dark
          ? AppColors.darkElevated
          : AppColors.lightCard,
      // Leading stripe in the semantic colour, so the variant is legible even
      // before the icon is parsed.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSemantic.overlayRadius),
        side: BorderSide(color: accent, width: AppSemantic.focusedBorderWidth),
      ),
      duration:
          action != null ? const Duration(seconds: 6) : const Duration(seconds: 4),
      action: action,
      content: Semantics(
        liveRegion: true,
        label: '${kind.semanticPrefix}: $message',
        child: ExcludeSemantics(
          child: Row(
            children: [
              Icon(kind.icon, color: accent, size: AppIconSize.sm),
              const SizedBox(width: AppSemantic.iconGap),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Confirms an action completed. Use only when something actually changed.
void showSuccess(BuildContext context, String message) =>
    _show(context, message, _Kind.success);

/// Reports a failure. Accepts a raw error object and routes it through
/// [friendlyError], so call sites stop hand-formatting exception text.
void showError(BuildContext context, Object error) =>
    _show(context, error is String ? error : friendlyError(error), _Kind.error);

/// Neutral status that is neither success nor failure.
void showInfo(BuildContext context, String message) =>
    _show(context, message, _Kind.info);

/// Success plus a reversal affordance. Prefer this over a confirmation dialog
/// for anything genuinely undoable — it is faster and less interruptive.
void showUndo(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
  String label = 'Undo',
}) =>
    _show(
      context,
      message,
      _Kind.success,
      action: SnackBarAction(
        label: label,
        textColor: AppColors.iconAccent(context),
        onPressed: onUndo,
      ),
    );

/// A destructive confirmation with consistent shape, ordering and tone.
///
/// Returns true only on explicit confirm; a barrier tap or back gesture is a
/// cancel. The destructive button is deliberately NOT autofocused — a stray
/// Enter must never delete a team.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        // Cancel first: the safe choice sits where the thumb rests.
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          autofocus: false,
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
