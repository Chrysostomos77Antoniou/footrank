import 'package:flutter/material.dart';

/// Professional Material icon for a player's position.
IconData positionIcon(String? position) {
  switch (position) {
    case 'Goalkeeper':
      return Icons.sports_handball;
    case 'Defender':
      return Icons.shield_outlined;
    case 'Midfielder':
      return Icons.hub_outlined;
    case 'Forward':
      return Icons.bolt;
    default:
      return Icons.directions_run;
  }
}

/// Small emoji helpers for visual flair.
String positionEmoji(String? position) {
  switch (position) {
    case 'Goalkeeper':
      return '🧤';
    case 'Defender':
      return '🛡️';
    case 'Midfielder':
      return '⚙️';
    case 'Forward':
      return '⚡';
    default:
      return '👟';
  }
}

String rankEmoji(int rank) {
  switch (rank) {
    case 1:
      return '🥇';
    case 2:
      return '🥈';
    case 3:
      return '🥉';
    default:
      return '#$rank';
  }
}
