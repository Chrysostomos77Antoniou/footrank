import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';

/// Rounded back button used in app bars so every pushed page shares the same
/// header. Pair with [kBackChipLeadingWidth] on the [AppBar].
const double kBackChipLeadingWidth = 84;

class BackChip extends StatelessWidget {
  const BackChip({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: AppSemantic.screenPadding),
      child: Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: Semantics(
            button: true,
            label: 'Back',
            excludeSemantics: true,
            child: Material(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppSemantic.controlRadius),
                side: BorderSide(color: AppColors.border(context)),
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppSemantic.controlRadius),
                ),
                onTap: () => Navigator.of(context).maybePop(),
                child: Icon(Icons.chevron_left_rounded,
                    size: 26, color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
