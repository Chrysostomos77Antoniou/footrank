import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/premium.dart';

/// Interaction primitives for the admin panel.
///
/// The rules they encode (from Emil Kowalski's design-engineering notes):
///
/// * Anything pressable answers the press immediately: a subtle scale-down
///   (0.97) for controls, a tint for table rows.
/// * Hover effects are hover-only (mouse); touch never gets a stuck state.
/// * Enter with a strong ease-out, never ease-in. Exits are quicker than
///   entrances. Nothing appears from scale(0) -- popovers/dialogs start at
///   0.96 and fade.
/// * Popovers scale from the corner nearest their trigger; modals stay
///   centred.
/// * High-frequency interactions (switching filters, switching sections)
///   do NOT animate -- they should feel instant.
/// * Everything honours reduced motion.

/// Strong ease-out -- the built-in curves are too timid for UI.
const Curve kAdminEaseOut = Cubic(0.23, 1, 0.32, 1);

/// Strong ease-in-out -- for things that move while staying on screen.
const Curve kAdminEaseInOut = Cubic(0.77, 0, 0.175, 1);

const Duration kAdminHover = Duration(milliseconds: 150);
const Duration kAdminPress = Duration(milliseconds: 120);

/// Modal dialog with a scale(0.96)+fade entrance from the centre.
///
/// Replaces plain `showDialog`, whose default is a bare fade. Modals are
/// seen occasionally, so a ~200ms entrance is appropriate; the exit uses a
/// plain ease-out so it clears the screen quickly.
/// Below this width the panel switches to its phone layout: bottom tab bar,
/// card rows instead of tables, scrolling chip rows.
const double kAdminPhoneBreakpoint = 700;

bool isAdminPhone(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kAdminPhoneBreakpoint;

/// iOS-style drawer curve: fast out, long settle.
const Curve kAdminDrawer = Cubic(0.32, 0.72, 0, 1);

Future<T?> showAdminDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final phone = isAdminPhone(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: reduceMotion(context)
        ? Duration.zero
        : Duration(milliseconds: phone ? 300 : 200),
    pageBuilder: (ctx, _, _) => SafeArea(
      // On a phone the dialog gets nearly the full width -- the default
      // 40px side inset leaves forms cramped.
      child: phone
          ? Theme(
              data: Theme.of(ctx).copyWith(
                dialogTheme: Theme.of(ctx).dialogTheme.copyWith(
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 24,
                  ),
                ),
              ),
              child: builder(ctx),
            )
          : builder(ctx),
    ),
    transitionBuilder: (ctx, animation, _, child) {
      if (phone) {
        // Rises from below like a sheet; exits faster than it enters.
        final rise = CurvedAnimation(
          parent: animation,
          curve: kAdminDrawer,
          reverseCurve: Curves.easeOut,
        );
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(rise),
            child: child,
          ),
        );
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: kAdminEaseOut,
        reverseCurve: Curves.easeOut,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Scales its child down while any pointer is pressed on it.
///
/// Uses a [Listener], which never joins the gesture arena -- so it can wrap
/// a [FilledButton], chip or row without interfering with its own tap.
class AdminPressScale extends StatefulWidget {
  final Widget child;
  final double scale;
  final bool enabled;

  const AdminPressScale({
    super.key,
    required this.child,
    this.scale = 0.97,
    this.enabled = true,
  });

  @override
  State<AdminPressScale> createState() => _AdminPressScaleState();
}

class _AdminPressScaleState extends State<AdminPressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || reduceMotion(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: kAdminPress,
        curve: kAdminEaseOut,
        child: widget.child,
      ),
    );
  }
}

/// A tappable table row / menu row.
///
/// Mouse hover tints the row, a press tints it in the brand colour, and it
/// is keyboard focusable (Enter/Space activate). Deliberately has no
/// Material ripple -- the tint is quicker and calmer on a dense table.
class AdminRowTile extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Background at rest -- e.g. a faint gold wash on a disputed match.
  final Color? tint;

  const AdminRowTile({
    super.key,
    required this.child,
    this.onTap,
    this.tint,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: 10,
    ),
    this.radius = AppRadius.md,
  });

  @override
  State<AdminRowTile> createState() => _AdminRowTileState();
}

class _AdminRowTileState extends State<AdminRowTile> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final brand = AppColors.brand(context);
    final color = _down
        ? brand.withValues(alpha: 0.12)
        : _focus
        ? onSurface.withValues(alpha: 0.08)
        : _hover
        ? onSurface.withValues(alpha: 0.05)
        : (widget.tint ?? Colors.transparent);

    final tile = AnimatedContainer(
      duration: reduceMotion(context) ? Duration.zero : kAdminHover,
      curve: Curves.ease,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: widget.child,
    );
    if (widget.onTap == null) return tile;

    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap!();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          child: tile,
        ),
      ),
    );
  }
}

/// Pill-shaped filter toggle with animated selection.
///
/// Replaces Material's [ChoiceChip]: colour, border and label transition
/// together over 150ms, the chip presses in (0.97), and an optional
/// [count] is shown in tabular figures so the pill doesn't jitter width.
class AdminFilterChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  /// Shows a caret (for chips that open a popover). Rotates when [open].
  final bool caret;
  final bool open;

  const AdminFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
    this.caret = false,
    this.open = false,
  });

  @override
  State<AdminFilterChip> createState() => _AdminFilterChipState();
}

class _AdminFilterChipState extends State<AdminFilterChip> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.brand(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = AppColors.muted(context);
    final selected = widget.selected;
    final dur = reduceMotion(context) ? Duration.zero : kAdminHover;

    final bg = selected
        ? brand.withValues(alpha: 0.14)
        : (_hover || _focus)
        ? onSurface.withValues(alpha: 0.06)
        : Colors.transparent;
    final border = selected
        ? brand.withValues(alpha: 0.55)
        : AppColors.inputBorder(context);
    final fg = selected ? brand : muted;

    return AdminPressScale(
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: dur,
              curve: Curves.ease,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppSemantic.pill),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                  ],
                  AnimatedDefaultTextStyle(
                    duration: dur,
                    curve: Curves.ease,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: fg,
                    ),
                    child: Text(widget.label),
                  ),
                  if (widget.count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${widget.count}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fg.withValues(alpha: 0.7),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (widget.caret) ...[
                    const SizedBox(width: 2),
                    AnimatedRotation(
                      turns: widget.open ? 0.5 : 0,
                      duration: reduceMotion(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      curve: kAdminEaseOut,
                      child: Icon(Icons.expand_more, size: 18, color: fg),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anchored popover menu that scales in from the corner nearest its trigger
/// (not from the centre), closes on outside-tap or Escape, and exits faster
/// than it enters.
class AdminPopover extends StatefulWidget {
  /// Builds the trigger. Call `toggle` to open/close; `open` is the state.
  final Widget Function(BuildContext context, VoidCallback toggle, bool open)
  triggerBuilder;

  /// Builds the menu contents. Call `close` to dismiss.
  final Widget Function(BuildContext context, VoidCallback close) menuBuilder;

  /// Anchor the menu's right edge to the trigger's right edge.
  final bool alignEnd;

  /// Fixed menu width.
  final double width;

  const AdminPopover({
    super.key,
    required this.triggerBuilder,
    required this.menuBuilder,
    this.alignEnd = false,
    this.width = 220,
  });

  @override
  State<AdminPopover> createState() => _AdminPopoverState();
}

class _AdminPopoverState extends State<AdminPopover>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 170),
    reverseDuration: const Duration(milliseconds: 110),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _c,
    curve: kAdminEaseOut,
    reverseCurve: Curves.easeOut,
  );
  bool _open = false;

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  void _show() {
    setState(() => _open = true);
    _portal.show();
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  Future<void> _close() async {
    if (!_open) return;
    setState(() => _open = false);
    if (!reduceMotion(context)) await _c.reverse();
    if (!mounted) return;
    _c.value = 0;
    _portal.hide();
  }

  void _toggle() => _open ? _close() : _show();

  @override
  Widget build(BuildContext context) {
    final end = widget.alignEnd;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _close,
            },
            child: Focus(
              autofocus: true,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _close,
                    ),
                  ),
                  CompositedTransformFollower(
                    link: _link,
                    showWhenUnlinked: false,
                    targetAnchor: end
                        ? Alignment.bottomRight
                        : Alignment.bottomLeft,
                    followerAnchor: end
                        ? Alignment.topRight
                        : Alignment.topLeft,
                    offset: const Offset(0, 6),
                    child: FadeTransition(
                      opacity: _curve,
                      child: ScaleTransition(
                        // Grows out of the trigger's corner, not the centre.
                        alignment: end ? Alignment.topRight : Alignment.topLeft,
                        scale: Tween<double>(
                          begin: 0.96,
                          end: 1,
                        ).animate(_curve),
                        child: Material(
                          color: isDark
                              ? AppColors.darkElevated
                              : AppColors.lightCard,
                          elevation: 0,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          clipBehavior: Clip.antiAlias,
                          child: Container(
                            width: widget.width,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              border: Border.all(
                                color: AppColors.inputBorder(context),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: isDark ? 0.45 : 0.12,
                                  ),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: widget.menuBuilder(context, _close),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: widget.triggerBuilder(context, _toggle, _open),
      ),
    );
  }
}

/// One row inside an [AdminPopover] menu: optional check, label, hint.
class AdminMenuItem extends StatelessWidget {
  final String label;
  final bool checked;
  final String? hint;
  final VoidCallback onTap;

  const AdminMenuItem({
    super.key,
    required this.label,
    required this.onTap,
    this.checked = false,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.brand(context);
    return AdminRowTile(
      onTap: onTap,
      radius: AppRadius.sm,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: AnimatedOpacity(
              opacity: checked ? 1 : 0,
              duration: reduceMotion(context) ? Duration.zero : kAdminHover,
              child: Icon(Icons.check, size: 16, color: brand),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: checked ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 16),
            Text(
              hint!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Skeleton for a loading admin table: shimmering rows inside the same card
/// the real table uses, so the content swap doesn't jump.
class AdminTableSkeleton extends StatelessWidget {
  final int rows;
  const AdminTableSkeleton({super.key, this.rows = 7});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: GlassCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            children: [
              for (var i = 0; i < rows; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const ShimmerBox(width: 32, height: 32, radius: 16),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ShimmerBox(
                            width: 120.0 + (i % 3) * 30,
                            height: 12,
                            radius: 6,
                          ),
                        ),
                      ),
                      const Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ShimmerBox(width: 70, height: 12, radius: 6),
                        ),
                      ),
                      const Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ShimmerBox(width: 100, height: 12, radius: 6),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading / error / content for an async admin list, crossfading between
/// states instead of hard-cutting (and no longer spinning forever on error).
///
/// While [future] is re-fetching, the previous data stays on screen, so
/// reloads after an edit don't flash back to a skeleton.
class AdminAsyncBody<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;

  /// Shown while loading; defaults to a table skeleton.
  final Widget? loading;

  const AdminAsyncBody({
    super.key,
    required this.future,
    required this.builder,
    this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        final Widget body;
        final String key;
        if (snapshot.hasData) {
          key = 'content';
          body = builder(context, snapshot.data as T);
        } else if (snapshot.hasError) {
          key = 'error';
          body = _AdminErrorState(message: friendlyError(snapshot.error!));
        } else {
          key = 'loading';
          body = loading ?? const AdminTableSkeleton();
        }
        return AsyncSwitcher(switcherKey: key, child: body);
      },
    );
  }
}

class _AdminErrorState extends StatelessWidget {
  final String message;
  const _AdminErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppColors.danger),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive card surface: border and glow warm up on hover, the whole
/// card presses in slightly, and an optional [accent] washes the corner with
/// colour so a card that needs attention reads differently from one that
/// doesn't. [builder] receives the hover state so inner details (an arrow
/// nudging right, say) can respond to it.
class AdminTile extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;

  /// Tint for the border, corner wash and hover glow.
  final Color? accent;

  /// Whether the [accent] wash + stronger border are shown at rest.
  final bool lit;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Big faint emoji tucked into the bottom-right corner -- gives the tile a
  /// picture without competing with the number. Nudges up on hover.
  final String? watermark;

  const AdminTile({
    super.key,
    required this.builder,
    this.onTap,
    this.accent,
    this.watermark,
    this.lit = false,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.radius = AppSemantic.cardRadius,
  });

  @override
  State<AdminTile> createState() => _AdminTileState();
}

class _AdminTileState extends State<AdminTile> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accent ?? AppColors.brand(context);
    final interactive = widget.onTap != null;
    final hot = interactive && (_hover || _focus);
    final lit = widget.lit;

    final border = lit
        ? accent.withValues(alpha: hot ? 0.7 : 0.38)
        : hot
        ? accent.withValues(alpha: 0.4)
        : AppColors.border(context);

    final card = AnimatedContainer(
      duration: reduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.ease,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        gradient: lit
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: const Alignment(0.6, 0.9),
                colors: [
                  accent.withValues(alpha: isDark ? 0.18 : 0.12),
                  accent.withValues(alpha: 0),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: border),
        boxShadow: hot
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.14),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: SizedBox(
        width: double.infinity,
        child: widget.builder(context, hot),
      ),
    );
    final mark = widget.watermark;
    final Widget body = mark == null
        ? card
        : Stack(
            fit: StackFit.passthrough,
            children: [
              card,
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(widget.radius),
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: AnimatedSlide(
                        duration: reduceMotion(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: kAdminEaseOut,
                        offset: Offset(0.12, hot ? 0.08 : 0.2),
                        child: Transform.rotate(
                          angle: -0.21,
                          child: Opacity(
                            opacity: isDark ? 0.16 : 0.2,
                            child: Text(
                              mark,
                              style: const TextStyle(fontSize: 60, height: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
    if (!interactive) return body;

    return AdminPressScale(
      scale: 0.985,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap!();
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Emoji that stands in for an icon on tiles -- friendlier than a flat glyph.
final Map<IconData, String> _kIconEmoji = {
  Icons.flag_rounded: '\u{1F6A9}',
  Icons.gavel_rounded: '\u2696\uFE0F',
  Icons.person_search_rounded: '\u{1F50E}',
  Icons.pending_actions_rounded: '\u23F3',
  Icons.shield_rounded: '\u{1F6E1}\uFE0F',
  Icons.place_rounded: '\u{1F4CD}',
  Icons.sports_soccer_rounded: '\u26BD',
  Icons.visibility_rounded: '\u{1F440}',
  Icons.fact_check_rounded: '\u2705',
  Icons.location_city_rounded: '\u{1F3D9}\uFE0F',
  Icons.bolt_rounded: '\u26A1',
  Icons.emoji_events_rounded: '\u{1F3C6}',
  Icons.people_alt_rounded: '\u{1F465}',
  Icons.people_rounded: '\u{1F465}',
  Icons.verified_rounded: '\u{1F4AF}',
  Icons.person_add_rounded: '\u{1F195}',
  Icons.euro_rounded: '\u{1F4B6}',
  Icons.event_available_rounded: '\u{1F3DF}\uFE0F',
  Icons.calendar_month_rounded: '\u{1F4C5}',
  Icons.check_circle_rounded: '\u2705',
};

/// The emoji for [icon], or null if it has none.
String? adminEmojiFor(IconData icon) => _kIconEmoji[icon];

/// Rounded well used on tiles. Shows the icon's emoji when it has one.
class AdminIconChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const AdminIconChip({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final emoji = adminEmojiFor(icon);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: emoji == null ? color.withValues(alpha: 0.15) : null,
        gradient: emoji == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.28),
                  color.withValues(alpha: 0.08),
                ],
              ),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: emoji == null
          ? Icon(icon, color: color, size: size * 0.52)
          : Text(emoji, style: TextStyle(fontSize: size * 0.5, height: 1)),
    );
  }
}

/// A row of filter chips: wraps on desktop, scrolls sideways on a phone so
/// the controls stay on one tidy line instead of stacking three deep.
class AdminFilterBar extends StatelessWidget {
  final List<Widget> children;
  const AdminFilterBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    if (!isAdminPhone(context)) {
      return Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Let chips slide out under the page gutter instead of clipping at it.
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xs),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Fixed-gap responsive grid: as many columns as fit [minTileWidth], tiles
/// stretched to fill the row.
class AdminGrid extends StatelessWidget {
  final int count;
  final double minTileWidth;

  /// Columns on a phone, where [minTileWidth] would otherwise force a single
  /// tall column. Use 1 for tiles that need the full width.
  final int phoneColumns;
  final Widget Function(int index, double width) itemBuilder;

  /// On a phone, lay the tiles out as one horizontally scrolling strip of
  /// compact tiles instead of a tall grid, so the list below stays on screen.
  final bool phoneScroll;

  const AdminGrid({
    super.key,
    required this.count,
    required this.minTileWidth,
    required this.itemBuilder,
    this.phoneColumns = 2,
    this.phoneScroll = false,
  });

  @override
  Widget build(BuildContext context) {
    final phone = isAdminPhone(context);
    final gap = phone ? AppSpacing.sm : AppSpacing.md;
    if (phone && phoneScroll) {
      const tileW = 188.0;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        physics: const BouncingScrollPhysics(),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) SizedBox(width: gap),
                SizedBox(width: tileW, child: itemBuilder(i, tileW)),
              ],
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final cols = phone
            ? phoneColumns.clamp(1, count)
            : ((c.maxWidth + gap) / (minTileWidth + gap)).floor().clamp(
                1,
                count,
              );
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        // Rows share a height, so a tile with a progress bar doesn't leave
        // its neighbour looking short.
        final rows = <Widget>[];
        for (var start = 0; start < count; start += cols) {
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < cols; j++) ...[
                    if (j > 0) SizedBox(width: gap),
                    SizedBox(
                      width: w,
                      child: start + j < count
                          ? itemBuilder(start + j, w)
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// A compact summary tile for the top of a page: icon, big value, label and
/// an optional progress bar that fills on first show.
class AdminMiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  /// 0..1 -- draws a progress bar under the label.
  final double? progress;
  final bool lit;
  final VoidCallback? onTap;

  /// Position in a row of tiles -- drives the entrance stagger.
  final int index;

  const AdminMiniStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
    this.progress,
    this.lit = false,
    this.onTap,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.brand(context);
    return FadeSlideIn(
      delay: AppMotion.staggerFor(index),
      animateOnceId: 'admin-mini-$label',
      offsetY: 6,
      child: AdminTile(
        accent: c,
        lit: lit,
        onTap: onTap,
        watermark: adminEmojiFor(icon),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        builder: (context, hovered) => Builder(
          builder: (context) {
            // In a two-up phone grid the tile is ~160px wide: stack the
            // chip above the number instead of squeezing them side by side.
            // (A plain flag, not LayoutBuilder: the grid sizes rows with
            // IntrinsicHeight, which LayoutBuilder can't answer.)
            final stacked = isAdminPhone(context);
            final valueText = Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            );
            final labelText = Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            );
            final body = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                valueText,
                const SizedBox(height: 2),
                labelText,
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  _ProgressBar(value: progress!, color: c),
                ],
              ],
            );
            if (stacked) {
              // Compact phone tile: small chip beside value + label, so a
              // strip of them stays about 60px tall.
              return Row(
                children: [
                  AdminIconChip(icon: icon, color: c, size: 30),
                  const SizedBox(width: 10),
                  Expanded(child: body),
                ],
              );
            }
            return Row(
              children: [
                AdminIconChip(icon: icon, color: c, size: 38),
                const SizedBox(width: 12),
                Expanded(child: body),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  const _ProgressBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.08);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: reduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 700),
      curve: kAdminEaseOut,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Container(height: 5, color: track),
            FractionallySizedBox(
              widthFactor: v,
              child: Container(height: 5, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Search box with a built-in clear button and a brand-coloured focus ring.
class AdminSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  const AdminSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  @override
  State<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends State<AdminSearchField> {
  late final TextEditingController _c =
      widget.controller ?? TextEditingController();

  @override
  void initState() {
    super.initState();
    _c.addListener(_onText);
  }

  void _onText() => setState(() {});

  @override
  void dispose() {
    _c.removeListener(_onText);
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );
    return TextField(
      controller: _c,
      onChanged: widget.onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: widget.hint,
        isDense: true,
        filled: true,
        fillColor: onSurface.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: Theme.of(context).hintColor,
        ),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _c.clear();
                  widget.onChanged('');
                },
              ),
        border: border(AppColors.inputBorder(context)),
        enabledBorder: border(AppColors.inputBorder(context)),
        focusedBorder: border(
          AppColors.brand(context).withValues(alpha: 0.7),
          1.5,
        ),
      ),
    );
  }
}
