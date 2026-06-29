import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:footrank/core/theme/app_colors.dart';

/// App background: a layered, gently-drifting gradient. In dark mode it stacks
/// several shades of near-black navy with a faint accent glow; in light mode,
/// several shades of white/grey. Subtle and slow — alive, not busy.
class AmbientBackground extends StatefulWidget {
  final Widget child;
  const AmbientBackground({super.key, required this.child});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).scaffoldBackgroundColor;
    // Lighter + darker tints of the base, plus a faint brand glow, give the
    // flat surface depth without ever reading as a colour wash.
    final lighter = isDark
        ? const Color(0xFF1B2238).withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.9);
    final darker = isDark
        ? const Color(0xFF070A16).withValues(alpha: 0.7)
        : const Color(0xFFE6E9F0).withValues(alpha: 0.8);
    final glow = AppColors.brand(context).withValues(alpha: isDark ? 0.07 : 0.05);

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [const Color(0xFF0C1124), base, const Color(0xFF090C1A)]
                  : [Colors.white, base, const Color(0xFFECEEF3)],
            ),
          ),
          child: CustomPaint(
            painter: _AmbientBlobs(
                t: t, lighter: lighter, darker: darker, glow: glow),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _AmbientBlobs extends CustomPainter {
  final double t;
  final Color lighter, darker, glow;
  _AmbientBlobs(
      {required this.t,
      required this.lighter,
      required this.darker,
      required this.glow});

  void _blob(Canvas c, Offset center, double r, Color color) {
    final rect = Rect.fromCircle(center: center, radius: r);
    final paint = Paint()
      ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
          .createShader(rect);
    c.drawCircle(center, r, paint);
  }

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    _blob(c, Offset(w * (0.16 + 0.10 * t), h * (0.10 + 0.05 * t)), w * 0.62,
        lighter);
    _blob(c, Offset(w * (0.92 - 0.12 * t), h * (0.34 + 0.06 * t)), w * 0.55,
        glow);
    _blob(c, Offset(w * (0.72 + 0.10 * t), h * (0.88 - 0.06 * t)), w * 0.68,
        darker);
  }

  @override
  bool shouldRepaint(_AmbientBlobs old) => old.t != t;
}

/// Clean solid card with a subtle border + soft neutral shadow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 16,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        // A faint top-to-bottom shade gives the card depth instead of a flat fill.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.darkElevated.withValues(alpha: 0.85),
                  AppColors.darkCard,
                ]
              : [Colors.white, const Color(0xFFF7F8FB)],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
            blurRadius: isDark ? 18 : 10,
            offset: const Offset(0, 6),
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

/// Scales down briefly on tap for a tactile micro-interaction.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const PressableScale({super.key, required this.child, required this.onTap});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.985),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
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
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 24,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  // Minimal motion: a single quick fade, no slide, no stagger — content
  // appears almost instantly for a calm, professional feel.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fade, child: widget.child);
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
