import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/premium.dart';

/// Secondary ink used on the frosted light card (a touch stronger than
/// [AppColors.lightSecondary] because the glass sits over a dark video).
const Color _frostInk = Color(0xFF2F3D35);

/// Marks the subtree as sitting on the see-through [AuthCard] so fields and
/// labels pick the glass-friendly colours.
class _AuthSurface extends InheritedWidget {
  final bool frosted;
  const _AuthSurface({required this.frosted, required super.child});

  @override
  bool updateShouldNotify(_AuthSurface old) => old.frosted != frosted;
}

/// Colours shared by the auth widgets, resolved from the theme and from the
/// surface (frosted video card vs. solid card) they are placed on.
class AuthTone {
  final bool dark;
  final bool frosted;
  final Color text;
  final Color inputBorder;

  const AuthTone._({
    required this.dark,
    required this.frosted,
    required this.text,
    required this.inputBorder,
  });

  static AuthTone of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_AuthSurface>();
    return AuthTone._(
      dark: Theme.of(context).brightness == Brightness.dark,
      frosted: scope?.frosted ?? false,
      text: Theme.of(context).colorScheme.onSurface,
      inputBorder: AppColors.inputBorder(context),
    );
  }

  /// Labels, helper text and "or".
  Color get secondary => dark
      ? AppColors.darkSecondary
      : (frosted ? _frostInk : AppColors.lightSecondary);

  /// Small helper text under a field.
  Color get hint => dark ? const Color(0xFF8F9BA8) : secondary;

  /// Leading/trailing icons inside a field.
  Color get fieldIcon => dark ? const Color(0xFFAEB9C4) : secondary;

  /// Field fill.
  Color get fieldFill => dark
      ? AppColors.darkElevated
      : (frosted ? Colors.white.withValues(alpha: 0.55) : Colors.white);

  /// Focus ring and cursor.
  Color get focus => dark ? AppColors.lime : AppColors.limeDeep;

  /// Inline links on glass or card.
  Color get link => dark ? AppColors.lime : AppColors.limeDeeper;

  /// Hairline divider.
  Color get divider => dark
      ? Colors.white.withValues(alpha: 0.12)
      : AppColors.ink.withValues(alpha: 0.12);
}

/// Text field used on the auth screens: 52px tall, radius 14, with a small
/// label above the value and a leading icon.
class AuthField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final FocusNode? focusNode;

  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.autofillHints,
    this.textInputAction,
    this.onFieldSubmitted,
    this.focusNode,
  });

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  // Only relevant when widget.obscure is true; lets the user reveal a
  // password instead of it being permanently hidden with no way to check it.
  bool _reveal = false;
  bool _focused = false;
  String? _error;
  FocusNode? _ownFocus;

  FocusNode get _node => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(AuthField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _node.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted && _focused != _node.hasFocus) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tone = AuthTone.of(context);
    final danger = AppColors.dangerText(context);
    final hasError = _error != null;
    final borderColor = hasError
        ? danger
        : (_focused ? tone.focus : tone.inputBorder);
    final borderWidth = (_focused || hasError)
        ? AppSemantic.focusedBorderWidth
        : AppSemantic.borderWidth;
    const none = InputBorder.none;

    return Container(
      constraints: const BoxConstraints(minHeight: AppSemantic.buttonHeight),
      padding: EdgeInsets.only(left: 14, right: widget.obscure ? 4 : 14),
      decoration: BoxDecoration(
        color: tone.fieldFill,
        borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Row(
        children: [
          Icon(widget.icon, size: AppIconSize.sm + 2, color: tone.fieldIcon),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: tone.secondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 13 / 11,
                    ),
                  ),
                  const SizedBox(height: 1),
                  TextFormField(
                    controller: widget.controller,
                    focusNode: _node,
                    obscureText: widget.obscure && !_reveal,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    onFieldSubmitted: widget.onFieldSubmitted,
                    autofillHints: widget.autofillHints,
                    // A password manager shouldn't get autocorrect/suggestions
                    // fighting it.
                    autocorrect: !widget.obscure,
                    enableSuggestions: !widget.obscure,
                    cursorColor: tone.focus,
                    style: TextStyle(
                      color: tone.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 18 / 15,
                    ),
                    validator: (v) {
                      final e = widget.validator?.call(v);
                      if (e != _error) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _error != e) {
                            setState(() => _error = e);
                          }
                        });
                      }
                      return e;
                    },
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      border: none,
                      enabledBorder: none,
                      disabledBorder: none,
                      focusedBorder: none,
                      errorBorder: none,
                      focusedErrorBorder: none,
                      errorMaxLines: 2,
                      errorStyle: TextStyle(
                        color: danger,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.obscure)
            IconButton(
              iconSize: AppIconSize.sm + 2,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: EdgeInsets.zero,
              icon: Icon(
                _reveal
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: tone.fieldIcon,
              ),
              tooltip: _reveal ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _reveal = !_reveal),
            ),
        ],
      ),
    );
  }
}

/// Lime primary button (ink text) used on the auth screens.
class AuthPrimaryButton extends StatelessWidget {
  final bool loading;
  final String label;
  final VoidCallback onPressed;

  const AuthPrimaryButton({
    super.key,
    required this.loading,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final onAction = AppColors.onAction(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PressableScale(
      onTap: loading ? () {} : onPressed,
      child: Container(
        height: AppSemantic.buttonHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.action,
          borderRadius: BorderRadius.circular(AppSemantic.buttonRadius),
          boxShadow: dark
              ? null
              : [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.14),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: loading
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: onAction,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  color: onAction,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

/// Social-auth button (Google / Apple / Facebook): 48px, radius 14, a plain
/// Material icon on the left and the label centred.
class AuthGoogleButton extends StatelessWidget {
  final bool loading;
  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  const AuthGoogleButton({
    super.key,
    required this.loading,
    required this.label,
    required this.onPressed,
    this.icon = Icons.g_mobiledata,
  });

  @override
  Widget build(BuildContext context) {
    final tone = AuthTone.of(context);
    final ink = tone.text;
    final glyph = icon == Icons.g_mobiledata ? 34.0 : 24.0;
    return Opacity(
      opacity: loading ? 0.7 : 1,
      child: PressableScale(
        onTap: loading ? () {} : onPressed,
        semanticLabel: label,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: tone.dark ? null : Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
            border: Border.all(color: tone.inputBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: Center(
                  child: loading
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ink,
                          ),
                        )
                      : OverflowBox(
                          maxWidth: glyph,
                          maxHeight: glyph,
                          child: Icon(icon, size: glyph, color: ink),
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 26),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints [shadows] only outside the rounded rect, the way a CSS box-shadow
/// does, so a see-through card is not darkened from behind.
class _OuterShadowPainter extends CustomPainter {
  final double radius;
  final List<BoxShadow> shadows;
  const _OuterShadowPainter({required this.radius, required this.shadows});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final outside = Path.combine(
      PathOperation.difference,
      Path()
        ..addRect(
          Rect.fromLTWH(-100, -100, size.width + 200, size.height + 300),
        ),
      Path()..addRRect(rrect),
    );
    canvas.save();
    canvas.clipPath(outside);
    for (final s in shadows) {
      canvas.drawRRect(rrect.shift(s.offset), s.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.radius != radius || old.shadows != shadows;
}

/// The card that wraps an auth form. By default it is frosted glass (blurred,
/// translucent) so the video behind shows through; pass `frosted: false` for
/// a solid card over a flat backdrop. [compact] is kept for API compatibility
/// (the card padding is the same on every screen size).
class AuthCard extends StatelessWidget {
  final Widget child;
  final bool compact;
  final bool frosted;
  const AuthCard({
    super.key,
    required this.child,
    this.compact = false,
    this.frosted = true,
  });

  static const double _radius = 24;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(_radius);
    final Color fill = frosted
        ? (dark
            ? AppColors.darkCard.withValues(alpha: 0.72)
            : Colors.white.withValues(alpha: 0.58))
        : (dark ? AppColors.darkCard : AppColors.lightCard);
    final shadows = dark
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ]
        : [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ];

    Widget surface = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(color: AppColors.border(context)),
      ),
      child: child,
    );
    if (frosted) {
      final sigma = dark ? 22.0 : 24.0;
      surface = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: surface,
        ),
      );
    }
    return _AuthSurface(
      frosted: frosted,
      child: CustomPaint(
        painter: _OuterShadowPainter(radius: _radius, shadows: shadows),
        child: surface,
      ),
    );
  }
}

/// Reusable "or" divider for auth screens.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final tone = AuthTone.of(context);
    final line = Expanded(child: Container(height: 1, color: tone.divider));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            'or',
            style: TextStyle(
              color: tone.secondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

/// Circular brand badge + title + subtitle shown above the auth card.
///
/// [overVideo] picks the subtitle ink: over the video scrim it is a soft
/// light grey in dark mode; on the flat pitch hero it is the muted secondary.
class AuthBrandBlock extends StatelessWidget {
  final String title;
  final String subtitle;
  final double badgeSize;
  final double titleSize;
  final bool overVideo;

  const AuthBrandBlock({
    super.key,
    required this.title,
    required this.subtitle,
    this.badgeSize = 64,
    this.titleSize = 30,
    this.overVideo = true,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = dark ? AppColors.darkOnSurface : Colors.white;
    final subColor = dark
        ? (overVideo ? const Color(0xFFD5DCE3) : AppColors.darkSecondary)
        : Colors.white.withValues(alpha: 0.9);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: badgeSize,
          height: badgeSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: dark
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.heroDarkA, AppColors.heroDarkB],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.limeDeeper, AppColors.limeDeeper],
                  ),
            border: Border.all(
              color: AppColors.lime.withValues(alpha: dark ? 0.35 : 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.4 : 0.25),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.sports_soccer,
            color: AppColors.lime,
            size: badgeSize * 0.56,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: titleColor,
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.01 * titleSize,
            height: 1.2,
          ),
        ),
        const SizedBox(height: AppSemantic.labelGap),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: subColor,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Stretches a radial gradient horizontally so a circular Flutter gradient
/// matches a CSS ellipse.
class _EllipseTransform extends GradientTransform {
  final double sx;
  const _EllipseTransform(this.sx);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final cx = bounds.center.dx;
    return Matrix4.identity()
      ..translate(cx, 0.0)
      ..scale(sx, 1.0)
      ..translate(-cx, 0.0);
  }
}

class _PitchHeroPainter extends CustomPainter {
  final Color line;
  final double circleCy;
  final double circleR;
  final double dotR;
  final double boxTop;
  final double boxW;
  final double boxH;
  final double boxVisible;

  const _PitchHeroPainter({
    required this.line,
    required this.circleCy,
    required this.circleR,
    required this.dotR,
    required this.boxTop,
    required this.boxW,
    required this.boxH,
    required this.boxVisible,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cx = size.width / 2;
    canvas.drawCircle(Offset(cx, circleCy), circleR, p);
    canvas.drawCircle(Offset(cx, circleCy), dotR, p);
    canvas.drawLine(Offset(0, circleCy), Offset(size.width, circleCy), p);
    canvas.drawRect(
      Rect.fromLTWH(boxVisible - boxW, boxTop, boxW, boxH),
      p,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width - boxVisible, boxTop, boxW, boxH),
      p,
    );
  }

  @override
  bool shouldRepaint(_PitchHeroPainter old) =>
      old.line != line ||
      old.circleCy != circleCy ||
      old.circleR != circleR ||
      old.boxTop != boxTop;
}

/// Pitch-line hero used at the top of the reset-password and onboarding
/// screens: a green wash with a soft lime glow and white pitch markings.
/// Dark = deep green fading into the page background; light = solid
/// Matchday green.
class AuthPitchHero extends StatelessWidget {
  final double height;
  final Widget? child;
  final double circleCy;
  final double circleR;
  final double dotR;
  final double boxTop;
  final double boxW;
  final double boxH;

  /// How many px of each penalty box stay inside the screen edge.
  final double boxVisible;
  final double glowAlpha;

  /// Vertical radius of the glow as a fraction of [height] (CSS "90%").
  final double glowRy;

  const AuthPitchHero({
    super.key,
    required this.height,
    this.child,
    this.circleCy = 160,
    this.circleR = 96,
    this.dotR = 4,
    this.boxTop = 50,
    this.boxW = 130,
    this.boxH = 200,
    this.boxVisible = 70,
    this.glowAlpha = 0.20,
    this.glowRy = 0.9,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final ry = glowRy * height;
          final rx = 1.2 * w;
          final shortest = w < height ? w : height;
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: dark
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF0F2E20),
                              Color(0xFF0C1A16),
                              Color(0xFF0C1015),
                            ],
                            stops: [0, 0.74, 1],
                          )
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.limeDeep, AppColors.limeDeeper],
                          ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: ry / shortest,
                      colors: [
                        AppColors.lime.withValues(alpha: glowAlpha),
                        AppColors.lime.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.62],
                      transform: _EllipseTransform(rx / ry),
                    ),
                  ),
                ),
                CustomPaint(
                  painter: _PitchHeroPainter(
                    line: Colors.white.withValues(alpha: dark ? 0.08 : 0.12),
                    circleCy: circleCy,
                    circleR: circleR,
                    dotR: dotR,
                    boxTop: boxTop,
                    boxW: boxW,
                    boxH: boxH,
                    boxVisible: boxVisible,
                  ),
                ),
                if (child != null) child!,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PitchFloorPainter extends CustomPainter {
  final Color line;
  const _PitchFloorPainter(this.line);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cx = size.width / 2;
    final b = size.height;
    canvas.drawCircle(Offset(cx, b), 120, p);
    canvas.drawCircle(Offset(cx, b), 4, p);
    canvas.drawLine(Offset(0, b), Offset(size.width, b), p);
    canvas.drawRect(Rect.fromLTWH(cx - 100, b - 110, 200, 120), p);
    canvas.drawRect(Rect.fromLTWH(cx - 50, b - 50, 100, 60), p);
  }

  @override
  bool shouldRepaint(_PitchFloorPainter old) => old.line != line;
}

/// Faint pitch markings along the bottom edge (reset-password backdrop).
class AuthPitchFloor extends StatelessWidget {
  const AuthPitchFloor({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: CustomPaint(
        size: const Size(double.infinity, 300),
        painter: _PitchFloorPainter(
          dark
              ? Colors.white.withValues(alpha: 0.05)
              : AppColors.limeDeep.withValues(alpha: 0.10),
        ),
      ),
    );
  }
}
