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
