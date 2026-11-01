/// One venue name typed by a captain that needs an admin's eyes: it matched
/// no court in the (private) courts list, matched one in another city, or was
/// reported by another player. Mirrors a row of `admin_list_flagged_venues()`.
///
/// The name was typed either on a match request (by the team that opened it)
/// or as the venue a captain *suggested* when proposing a match
/// ([proposalId] is then set and [teamName] / [captainName] describe the
/// proposing side, [targetTeamName] the team that received the proposal).
class FlaggedVenueModel {
  final String reviewId;
  final String? requestId;
  final String? matchId;

  /// Set when the name was typed on a match proposal (kept after the proposal
  /// is accepted, when [matchId] is set too).
  final String? proposalId;

  /// Exactly what the captain typed.
  final String venueText;

  /// `no_match` | `other_city` | `reported`.
  final String reason;
  final String? city;
  final DateTime? scheduledAt;
  final String? teamName;
  final String? captainName;

  /// For a suggestion: the team whose request received the proposal.
  final String? targetTeamName;
  final String? requestStatus;
  final int reportCount;

  /// The closest court in the courts list, if any scored high enough to be
  /// worth showing. Only ever visible to admins.
  final String? suggestedCourtId;
  final String? suggestedCourtName;
  final String? suggestedCourtCity;
  final double? matchScore;
  final DateTime createdAt;

  const FlaggedVenueModel({
    required this.reviewId,
    this.requestId,
    this.matchId,
    this.proposalId,
    required this.venueText,
    required this.reason,
    this.city,
    this.scheduledAt,
    this.teamName,
    this.captainName,
    this.targetTeamName,
    this.requestStatus,
    this.reportCount = 0,
    this.suggestedCourtId,
    this.suggestedCourtName,
    this.suggestedCourtCity,
    this.matchScore,
    required this.createdAt,
  });

  bool get isReported => reason == 'reported';

  /// Typed by the proposing captain on a match proposal rather than on a
  /// match request.
  bool get isSuggestion => proposalId != null;

  /// Short human label for [reason].
  String get reasonLabel => switch (reason) {
        'no_match' => 'No court match',
        'other_city' => 'Matches a court in another city',
        'reported' => reportCount > 1 ? 'Reported by $reportCount players' : 'Reported',
        _ => 'Needs review',
      };

  factory FlaggedVenueModel.fromJson(Map<String, dynamic> json) {
    return FlaggedVenueModel(
      reviewId: json['review_id'] as String,
      requestId: json['request_id'] as String?,
      matchId: json['match_id'] as String?,
      proposalId: json['proposal_id'] as String?,
      venueText: (json['venue_text'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? 'no_match',
      city: json['city'] as String?,
      scheduledAt: json['scheduled_at'] == null
          ? null
          : DateTime.parse(json['scheduled_at'] as String),
      teamName: json['team_name'] as String?,
      captainName: json['captain_name'] as String?,
      targetTeamName: json['target_team_name'] as String?,
      requestStatus: json['request_status'] as String?,
      reportCount: (json['report_count'] as num?)?.toInt() ?? 0,
      suggestedCourtId: json['suggested_court_id'] as String?,
      suggestedCourtName: json['suggested_court_name'] as String?,
      suggestedCourtCity: json['suggested_court_city'] as String?,
      matchScore: (json['match_score'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
