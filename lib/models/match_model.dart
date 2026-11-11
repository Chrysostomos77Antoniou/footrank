import 'package:footrank/models/venue_location.dart';

class MatchModel {
  final String id;
  final String? requestId;
  final String homeTeamId;
  final String awayTeamId;
  final String city;
  final DateTime scheduledAt;
  final String matchType;
  final String format;
  final String status; // confirmed | completed | cancelled
  final int? homeScore;
  final int? awayScore;
  final String? scoreProposedBy;
  final bool homeConfirmed;
  final bool awayConfirmed;
  final bool homeOk; // home captain confirmed the fixture
  final bool awayOk; // away captain confirmed the fixture
  final int? homeReportH; // home captain's reported home score
  final int? homeReportA; // home captain's reported away score
  final int? awayReportH; // away captain's reported home score
  final int? awayReportA; // away captain's reported away score
  final bool scoreDisputed;
  final DateTime createdAt;
  /// Venue name as typed by the captain who opened the request (free text,
  /// shown verbatim; null = not set). FootRank never shows names from its own
  /// courts list.
  final String? venueText;

  /// Where the venue is on the map (null for older matches).
  final VenueLocation? venueLocation;
  final String? cancelReason; // expired_no_score | null (only set when status == cancelled)

  /// unpaid | awaiting_payment | paid -- derived match-wide from both teams'
  /// fee rows. Advisory: nothing blocks an unpaid match from being played.
  final String paymentStatus;

  // ---- Court booking (who books, and whether it is done) ----
  /// The team that must book the court (null on older matches).
  final String? bookerTeamId;

  /// not_booked | booked | cancelled_unbooked | null (older matches).
  final String? courtBookingStatus;
  final DateTime? bookedAt;

  /// "I booked it" must be tapped before this, or the match cancels.
  final DateTime? bookingDeadlineAt;

  /// A "court full" suggestion is waiting for an answer.
  final bool venueChangeOpen;

  // Optional joined team fields
  final String? homeTeamName;
  final String? awayTeamName;
  final String? homeTeamLogo;
  final String? awayTeamLogo;
  final int? homeTeamRating;
  final int? awayTeamRating;
  final String? homeTeamRecord;
  final String? awayTeamRecord;

  const MatchModel({
    required this.id,
    this.requestId,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.city,
    required this.scheduledAt,
    required this.matchType,
    required this.format,
    required this.status,
    this.homeScore,
    this.awayScore,
    this.scoreProposedBy,
    this.homeConfirmed = false,
    this.awayConfirmed = false,
    this.homeOk = false,
    this.awayOk = false,
    this.homeReportH,
    this.homeReportA,
    this.awayReportH,
    this.awayReportA,
    this.scoreDisputed = false,
    required this.createdAt,
    this.venueText,
    this.venueLocation,
    this.cancelReason,
    this.paymentStatus = 'unpaid',
    this.bookerTeamId,
    this.courtBookingStatus,
    this.bookedAt,
    this.bookingDeadlineAt,
    this.venueChangeOpen = false,
    this.homeTeamName,
    this.awayTeamName,
    this.homeTeamLogo,
    this.awayTeamLogo,
    this.homeTeamRating,
    this.awayTeamRating,
    this.homeTeamRecord,
    this.awayTeamRecord,
  });

  static String? _recordOf(Map<String, dynamic>? team) {
    if (team == null) return null;
    final w = (team['wins'] as int?) ?? 0;
    final l = (team['losses'] as int?) ?? 0;
    final d = (team['draws'] as int?) ?? 0;
    final base = '${w}W · ${l}L';
    return d > 0 ? '$base · ${d}D' : base;
  }

  bool get hasScore => homeScore != null && awayScore != null;

  /// The booking flow applies (confirmed or cancelled matches with a Booker).
  bool get hasBookingFlow => bookerTeamId != null && courtBookingStatus != null;
  bool get isBooked => courtBookingStatus == 'booked';
  bool get needsBooking =>
      status == 'confirmed' && courtBookingStatus == 'not_booked';

  /// Name of the booking team, when the team names were joined.
  String? get bookerTeamName => bookerTeamId == null
      ? null
      : (bookerTeamId == homeTeamId ? homeTeamName : awayTeamName);

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.parse(v as String);

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    final home = json['home_team'] as Map<String, dynamic>?;
    final away = json['away_team'] as Map<String, dynamic>?;
    return MatchModel(
      id: json['id'] as String,
      requestId: json['request_id'] as String?,
      homeTeamId: json['home_team_id'] as String,
      awayTeamId: json['away_team_id'] as String,
      city: json['city'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      matchType: json['match_type'] as String,
      format: json['format'] as String,
      status: json['status'] as String,
      homeScore: json['home_score'] as int?,
      awayScore: json['away_score'] as int?,
      scoreProposedBy: json['score_proposed_by'] as String?,
      homeConfirmed: (json['home_confirmed'] as bool?) ?? false,
      awayConfirmed: (json['away_confirmed'] as bool?) ?? false,
      homeOk: (json['home_ok'] as bool?) ?? false,
      awayOk: (json['away_ok'] as bool?) ?? false,
      homeReportH: json['home_report_h'] as int?,
      homeReportA: json['home_report_a'] as int?,
      awayReportH: json['away_report_h'] as int?,
      awayReportA: json['away_report_a'] as int?,
      scoreDisputed: (json['score_disputed'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      venueText: json['venue_text'] as String?,
      venueLocation: VenueLocation.fromJson(json),
      cancelReason: json['cancel_reason'] as String?,
      paymentStatus: (json['payment_status'] as String?) ?? 'unpaid',
      bookerTeamId: json['booker_team_id'] as String?,
      courtBookingStatus: json['court_booking_status'] as String?,
      bookedAt: _date(json['booked_at']),
      bookingDeadlineAt: _date(json['booking_deadline_at']),
      venueChangeOpen: (json['venue_change_open'] as bool?) ?? false,
      homeTeamName: home?['name'] as String?,
      awayTeamName: away?['name'] as String?,
      homeTeamLogo: home?['logo_url'] as String?,
      awayTeamLogo: away?['logo_url'] as String?,
      homeTeamRating: home?['rating'] as int?,
      awayTeamRating: away?['rating'] as int?,
      homeTeamRecord: _recordOf(home),
      awayTeamRecord: _recordOf(away),
    );
  }
}
