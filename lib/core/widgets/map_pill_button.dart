import 'package:flutter/material.dart';

/// A clearly-labelled "Get Directions" pill (icon + text, not just an icon)
/// meant to sit legibly on top of a photo. Text-only icon buttons were easy
/// to miss/misread — this spells out what tapping it does.
class MapPillButton extends StatelessWidget {
  final VoidCallback onPressed;
  const MapPillButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.directions, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text(
                'Get Directions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
