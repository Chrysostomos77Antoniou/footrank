import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';

/// Shared presentation pieces for the Team feature (Pitch Night / Matchday).

/// Screen title style: Sora 26/800.
TextStyle teamTitleStyle(BuildContext context) => TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.26,
      height: 1.2,
      color: Theme.of(context).colorScheme.onSurface,
    );

/// Pushed-screen header: 44px back button + title.
class TeamPageHeader extends StatelessWidget {
  final String title;
  const TeamPageHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: Material(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
                side: BorderSide(color: AppColors.border(context)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.chevron_left,
                      size: 26, color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: teamTitleStyle(context)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 11/700 uppercase muted section label.
class TeamSectionLabel extends StatelessWidget {
  final String text;
  const TeamSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: AppColors.muted(context),
          ),
        ),
      ),
    );
  }
}

/// 13/600 muted label placed above a form field.
class TeamFieldLabel extends StatelessWidget {
  final String text;
  const TeamFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.muted(context),
        ),
      ),
    );
  }
}

/// Field decoration: h52, radius 14 (border/fill come from the theme).
InputDecoration teamFieldDecoration(
  BuildContext context, {
  required String hint,
  required IconData icon,
}) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, size: 20, color: AppColors.onChip(context)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
  );
}

/// 72px rounded icon well + title + subtitle used on create / join screens.
class TeamHero extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const TeamHero(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.chip(context),
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 36, color: AppColors.brand(context)),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.22,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.muted(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Captain / vice-captain badge: lime fill, ink text.
class TeamRoleBadge extends StatelessWidget {
  final String label;
  const TeamRoleBadge({super.key, this.label = 'C'});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label == 'C' ? 'Captain' : 'Vice captain',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: AppColors.action,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: AppColors.onAction(context),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// Team avatar: logo if present, otherwise initials on the green hero gradient.
class TeamInitialsAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  const TeamInitialsAvatar(
      {super.key, required this.name, this.imageUrl, this.size = 44});

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: CachedNetworkImageProvider(imageUrl!),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.heroGrad(context),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// Primary (lime) button style: h[height], radius 14.
ButtonStyle teamFilledStyle({double height = 48}) => FilledButton.styleFrom(
      minimumSize: Size(0, height),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSemantic.controlRadius)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );

/// Secondary outlined button style: dark = 24% white hairline, light = 1.5px
/// deep green on white.
ButtonStyle teamOutlinedStyle(BuildContext context, {double height = 48}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return OutlinedButton.styleFrom(
    minimumSize: Size(0, height),
    backgroundColor: isDark ? Colors.transparent : Colors.white,
    foregroundColor: isDark ? AppColors.darkOnSurface : AppColors.limeDeep,
    side: isDark
        ? BorderSide(color: Colors.white.withValues(alpha: 0.24))
        : const BorderSide(color: AppColors.limeDeep, width: 1.5),
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSemantic.controlRadius)),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
  );
}
