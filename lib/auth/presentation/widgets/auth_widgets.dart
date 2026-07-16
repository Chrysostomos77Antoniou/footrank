import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/widgets/premium.dart';

/// Dark, translucent text field used on the branded auth screens.
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

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: widget.obscure && !_reveal,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      autofillHints: widget.autofillHints,
      // A password manager shouldn't get autocorrect/suggestions fighting it.
      autocorrect: !widget.obscure,
      enableSuggestions: !widget.obscure,
      style: const TextStyle(color: Colors.white),
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        prefixIcon: Icon(
          widget.icon,
          color: Colors.white.withValues(alpha: 0.7),
        ),
        suffixIcon: widget.obscure
            ? IconButton(
                icon: Icon(
                  _reveal
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                tooltip: _reveal ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _reveal = !_reveal),
              )
            : null,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.lime, width: 1.6),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFB4A8)),
      ),
    );
  }
}

/// Lime primary button (navy text) used on the auth screens.
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
    return PressableScale(
      onTap: loading ? () {} : onPressed,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.lime,
          borderRadius: BorderRadius.circular(16),
        ),
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.navy,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

/// Glassy social-auth button for auth screens (Google / Apple).
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
    return OutlinedButton.icon(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
      ),
      icon: loading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: icon == Icons.g_mobiledata ? 26 : 20),
      label: Text(label),
    );
  }
}

/// The dark translucent card that wraps an auth form. [compact] tightens
/// the padding on shorter screens (e.g. iPhone 13) so the whole auth screen
/// fits without scrolling.
class AuthCard extends StatelessWidget {
  final Widget child;
  final bool compact;
  const AuthCard({super.key, required this.child, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}

/// Reusable "or" divider for auth screens.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.25))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ),
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.25))),
      ],
    );
  }
}
