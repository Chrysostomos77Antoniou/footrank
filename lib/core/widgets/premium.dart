import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/motion.dart';

/// App background: a flat, theme-colored surface (graphite in Pitch Night,
/// soft green-white in Matchday). The old gradient and glow blobs are gone:
/// flat grounds make the cards and the lime accents carry the hierarchy.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  const AmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: isDark ? AppColors.darkBg : AppColors.lightBg,
      child: child,
    );
  }
}

/// Clean solid card: flat surface, hairline border, a whisper of shadow in
/// light mode.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  /// Optional semantic wash (e.g. win/loss/draw) blended lightly into the
  /// card fill.
  final Color? tint;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = AppSemantic.cardRadius,
    this.onTap,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppColors.darkCard : AppColors.lightCard;
    final fill =
        tint == null ? base : Color.alphaBlend(tint!.withValues(alpha: 0.12), base);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: child,
    );

    if (onTap != null) {
      content = PressableScale(onTap: onTap!, child: content);
    }
    return content;
  }
}

/// Segmented tab switcher styled to match [GlassCard]. Pairs with an
/// [IndexedStack] (or similar) for the actual tab content -- this widget is
/// just the control, it doesn't manage a `TabController`.
class GlassTabs extends StatelessWidget {
  final int index;
  final List<String> tabs;
  final ValueChanged<int> onChanged;

  const GlassTabs({
    super.key,
    required this.index,
    required this.tabs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Segments stay equal-width (same clean look as before for 2-3 short
    // tabs), but the label is wrapped in a FittedBox that scales the text
    // down to fit its segment instead of wrapping onto a second line --
    // that's what broke with 4 longer tabs.
    return GlassCard(
      padding: const EdgeInsets.all(6),
      radius: AppSemantic.cardRadius,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: PressableScale(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                      vertical: 11, horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index == i
                        ? (Theme.of(context).brightness == Brightness.dark
                            ? AppColors.lime.withValues(alpha: 0.16)
                            : AppColors.lime)
                        : null,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tabs[i],
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: index == i
                            ? (Theme.of(context).brightness == Brightness.dark
                                ? AppColors.lime
                                : AppColors.ink)
                            : AppColors.muted(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Scales down briefly on tap for a tactile micro-interaction.
///
/// This is the app's signature press feel and it wraps ~60 tap targets
/// (every tappable [GlassCard], [GlassTabs], and the branded buttons). It was
/// a bare [GestureDetector], which meant all of those were **invisible to
/// TalkBack and VoiceOver** — a screen reader saw decorative content, not a
/// control. Adding [Semantics] here fixes every one of them at once.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  /// What a screen reader announces. Omit when the wrapped child already
  /// contains its own descriptive text — the default merges that text in.
  final String? semanticLabel;

  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    // Under reduced motion the haptic and the tap still fire; only the scale
    // is dropped. The feedback is the point, the movement is the flourish.
    final animate = !reduceMotion(context);

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      onTap: widget.onTap,
      child: GestureDetector(
        onTapDown: animate ? (_) => setState(() => _scale = 0.97) : null,
        onTapUp: animate ? (_) => setState(() => _scale = 1) : null,
        onTapCancel: animate ? () => setState(() => _scale = 1) : null,
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _scale,
          duration: AppMotion.press,
          // Begins and ends at rest on screen — Easing.standard, not an
          // entrance curve.
          curve: AppMotion.standard,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Counts up to [value] when first shown — makes stats feel alive. Restarts
/// the roll whenever [value] changes (e.g. after a rating update).
class AnimatedCount extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;
  final String prefix;
  final String suffix;
  const AnimatedCount(
    this.value, {
    super.key,
    this.style,
    this.duration = const Duration(milliseconds: 900),
    this.prefix = '',
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    // Roll up to the value the first time it's shown (and animate on change) —
    // makes ratings / Pitch Power feel alive.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) =>
          Text('$prefix${v.round()}$suffix', style: style),
    );
  }
}

/// A shimmering placeholder block used for skeleton loading states.
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 12,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.05);
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.11)
        : Colors.black.withValues(alpha: 0.025);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * 2 - 1; // -1 .. 1
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 0.6, 0),
              end: Alignment(t + 0.6, 0),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// A small, calm "live"/secure pulse dot — used to express activity & safety.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({super.key, required this.color, this.size = 8});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 2.4,
      height: widget.size * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_c.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.5,
                child: Container(
                  width: widget.size + widget.size * 1.4 * t,
                  height: widget.size + widget.size * 1.4 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color,
                  ),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One-shot fade + slide-up entrance, with optional stagger [delay].
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offsetY;

  /// Stable identity for an item in a long, scrollable list.
  ///
  /// `ListView.builder` disposes rows that scroll out of its cache extent and
  /// rebuilds them on the way back, which recreates this widget's [State] and
  /// restarts the controller — so rows visibly re-faded *mid-scroll*, which
  /// reads as flicker rather than as an entrance. Passing an id makes the
  /// entrance fire once per item per session.
  final Object? animateOnceId;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    // 12, not 24: less travel reads as more expensive, and a long cascade of
    // 24px jumps looks like the list is settling rather than arriving.
    this.offsetY = 12,
    this.animateOnceId,
  });

  /// Convenience for list builders: caps the stagger per [AppMotion.staggerFor]
  /// and wires up the once-per-item guard in one call.
  factory FadeSlideIn.listItem({
    Key? key,
    required Widget child,
    required int index,
    Object? id,
  }) =>
      FadeSlideIn(
        key: key,
        delay: AppMotion.staggerFor(index),
        animateOnceId: id ?? index,
        child: child,
      );

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  /// Ids whose entrance has already played. Bounded so a long session on a
  /// big leaderboard cannot grow it without limit — evicting the oldest entry
  /// only risks re-animating an item the user scrolled away from long ago.
  static final _seen = <Object>{};
  static const _seenCap = 500;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.enter,
  );
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _c, curve: AppMotion.easeOut);

  /// True when this item already animated earlier in the session.
  bool _skip = false;

  @override
  void initState() {
    super.initState();

    final id = widget.animateOnceId;
    if (id != null) {
      if (_seen.contains(id)) {
        _skip = true;
        _c.value = 1; // land in the finished state, no motion
        return;
      }
      if (_seen.length >= _seenCap) _seen.remove(_seen.first);
      _seen.add(id);
    }

    // Honor the stagger delay so lists cascade in instead of popping at once.
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Accessibility: skip the entrance entirely under reduced motion. Uses the
    // shared helper so iOS's Reduce Motion counts too — the old check read
    // MediaQuery.disableAnimations, which only Android ever sets.
    if (_skip || reduceMotion(context)) {
      return widget.child;
    }
    // Slide only — deliberately NO opacity fade.
    //
    // Fading text in from transparent made content unreadable for the length
    // of the entrance, and worse on every re-entry (tab switch, scroll-back).
    // In dark mode a half-faded #ECEEF1 over the navy card reads as dark grey;
    // in light mode a barely-faded #000000 over white is nearly invisible. The
    // colours were always correct — the animation was hiding them.
    //
    // Body text must sit at its full, contrast-checked colour at all times, so
    // the entrance is expressed purely as movement.
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, widget.offsetY * (1 - _curve.value)),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Text painted with a gradient.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Gradient? gradient;
  final TextAlign? textAlign;

  const GradientText(
    this.text, {
    super.key,
    required this.style,
    this.gradient,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    // Solid, high-contrast headings (no gradient) for a professional look.
    // Headings default to the Sora display face unless a family was set.
    final color = style.color ?? Theme.of(context).colorScheme.onSurface;
    final merged = style.copyWith(
      color: color,
      fontFamily: style.fontFamily ?? 'Sora',
    );
    return Text(text, style: merged, textAlign: textAlign);
  }
}

/// Professional numbered rank medal. Top 3 are coin-style gold/silver/bronze;
/// the rest are a clean accent-tinted disc.
class RankBadge extends StatelessWidget {
  final int rank;
  final double size;
  const RankBadge({super.key, required this.rank, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;
    final medal = switch (rank) {
      1 => AppColors.gold,
      2 => AppColors.silver,
      3 => AppColors.bronze,
      _ => AppColors.brand(context),
    };

    if (isTop3) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(medal, Colors.white, 0.35)!,
              medal,
              Color.lerp(medal, Colors.black, 0.25)!,
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1),
        ),
        alignment: Alignment.center,
        child: Text(
          '$rank',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: size * 0.42,
            shadows: const [
              Shadow(color: Colors.black26, offset: Offset(0, 1), blurRadius: 2),
            ],
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: medal.withValues(alpha: 0.12),
        border: Border.all(color: medal.withValues(alpha: 0.4), width: 1.4),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

/// Captain's armband badge — a "C" (or "VC") patch like real captains wear.
class CaptainArmband extends StatelessWidget {
  final String label; // 'C' or 'VC'
  const CaptainArmband({super.key, this.label = 'C'});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.brand(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: AppColors.onBrand(context).withValues(alpha: 0.35), width: 1.2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.onBrand(context),
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Pill chip with gradient fill, used for stats/badges.
class GradientPill extends StatelessWidget {
  final String text;
  final IconData? icon;
  const GradientPill({super.key, required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.iconAccent(context), size: 14),
            const SizedBox(width: 5),
          ],
          Text(text,
              style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
