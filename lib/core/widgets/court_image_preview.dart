import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';

/// Opens a court's photo at ~70% of the screen over a blurred, brand-tinted
/// backdrop — tap anywhere outside the photo (or the close button) to
/// dismiss. Shared so every "box with a court photo" behaves the same way.
Future<void> showCourtImagePreview(
  BuildContext context, {
  required String name,
  String? imageUrl,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _CourtImagePreview(name: name, imageUrl: imageUrl),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _CourtImagePreview extends StatelessWidget {
  final String name;
  final String? imageUrl;
  const _CourtImagePreview({required this.name, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          color: AppColors.brand(context).withValues(alpha: 0.35),
          alignment: Alignment.center,
          child: FractionallySizedBox(
            widthFactor: 0.7,
            heightFactor: 0.7,
            // Absorb taps on the photo itself so they don't fall through and
            // close the preview.
            child: GestureDetector(
              onTap: () {},
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl != null)
                      Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(context),
                      )
                    else
                      _placeholder(context),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.75),
                            ],
                          ),
                        ),
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
    color: AppColors.iconAccent(context).withValues(alpha: 0.15),
    alignment: Alignment.center,
    child: Icon(
      Icons.sports_soccer,
      size: 72,
      color: AppColors.iconAccent(context).withValues(alpha: 0.6),
    ),
  );
}
