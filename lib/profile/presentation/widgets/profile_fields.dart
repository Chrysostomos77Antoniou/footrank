import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';

/// Field label shown above an input (12 / 700, secondary colour), with the
/// helper line beneath handled by the input's own decoration.
class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const LabeledField({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.muted(context),
            ),
          ),
        ),
        const SizedBox(height: 6),
        MergeSemantics(child: Semantics(label: label, child: child)),
      ],
    );
  }
}

/// Input text style: 15 / 600 on the primary text colour.
TextStyle profileFieldTextStyle(BuildContext context) => TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    );

/// 52px-high, 14px-radius input (border/fill come from the app theme) with an
/// optional leading icon, matching the Profile mockups.
InputDecoration profileInputDecoration(
  BuildContext context, {
  IconData? icon,
  String? prefixText,
  String? hintText,
  String? helperText,
  double verticalPadding = 16,
}) {
  final muted = AppColors.muted(context);
  return InputDecoration(
    hintText: hintText,
    helperText: helperText,
    helperMaxLines: 2,
    helperStyle: TextStyle(fontSize: 12, height: 1.4, color: muted),
    hintStyle: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w600, color: muted),
    prefixText: prefixText,
    prefixStyle:
        TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: muted),
    prefixIcon: icon == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 14, right: 12),
            child: Icon(icon, size: 20),
          ),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    contentPadding:
        EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
  );
}
