import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';

/// App background: solid scaffold color with a very subtle line texture and a
/// soft accent glow at the top — adds depth without hurting readability.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  const AmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: base)),
        // soft accent glow, top-left
        Positioned(
          top: -120,
          left: -100,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.lime.withValues(alpha: isDark ? 0.08 : 0.10),
                AppColors.lime.withValues(alpha: 0),
              ]),
            ),
          ),
        ),
        // faint diagonal line texture
        Positioned.fill(
          child: CustomPaint(
            painter: _LineTexturePainter(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: isDark ? 0.025 : 0.03),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _LineTexturePainter extends CustomPainter {
  final Color color;
  const _LineTexturePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const gap = 26.0;
    // diagonal lines (45°) across the canvas
    for (double x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineTexturePainter oldDelegate) =>
      oldDelegate.color != color;
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
    this.radius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? AppColors.darkCard : AppColors.lightCard;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
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
      onTapDown: (_) => setState(() => _scale = 0.96),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
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
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(0, widget.offsetY / 100),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    // Cap the stagger so long lists don't drag on slowly.
    final capped = widget.delay > const Duration(milliseconds: 160)
        ? const Duration(milliseconds: 160)
        : widget.delay;
    Future.delayed(capped, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
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
    final g = gradient ?? AppColors.headingGrad(context);
    return ShaderMask(
      shaderCallback: (bounds) => g.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      blendMode: BlendMode.srcIn,
      child: Text(text, style: style, textAlign: textAlign),
    );
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
          border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: medal.withValues(alpha: 0.45),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brand(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.onBrand(context), size: 15),
            const SizedBox(width: 5),
          ],
          Text(text,
              style: TextStyle(
                  color: AppColors.onBrand(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ],
      ),
    );
  }
}
