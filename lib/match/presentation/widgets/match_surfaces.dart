import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';

/// Shared surface styling for the Match feature's dialogs, so every
/// `AlertDialog` here reads as one of the app's flat cards rather than a
/// Material tonal sheet.
Color matchDialogColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkCard
        : AppColors.lightCard;

ShapeBorder matchDialogShape(BuildContext context) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSemantic.cardRadius),
      side: BorderSide(color: AppColors.border(context)),
    );

/// 11/700, letter-spaced, muted: the small caps label used above groups.
TextStyle matchSectionLabelStyle(BuildContext context) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: AppColors.muted(context),
    );
