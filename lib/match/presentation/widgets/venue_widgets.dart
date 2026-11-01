import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/match/presentation/widgets/match_surfaces.dart';

/// Shown wherever a user-entered venue name appears. FootRank never displays
/// names from its own court list in the match flow, only what captains type.
const String kVenueDisclaimer =
    'Venue names are entered by users. FootRank is not affiliated with any venue.';

/// Longest venue name the server accepts.
const int kVenueMaxLength = 60;

/// Whitespace collapsed and trimmed -- the same cleanup the server applies, so
/// a preview shows exactly what will be stored and displayed.
String cleanVenueInput(String raw) =>
    raw.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Form validator for the venue field. The server re-checks everything (and
/// also rejects links, phone numbers and inappropriate text), this is just the
/// instant feedback.
String? validateVenueInput(String? value) {
  final v = cleanVenueInput(value ?? '');
  if (v.isEmpty) return 'Enter where you will play';
  final length = v.runes.length;
  if (length < 2 || length > kVenueMaxLength) return 'Use 2–60 characters';
  if (RegExp(r'\p{L}', unicode: true).allMatches(v).length < 2) {
    return "Enter the venue's name";
  }
  return null;
}

/// Same as [validateVenueInput] for a field that may be left empty (a venue
/// suggested on a proposal): empty is fine, anything typed must be a name.
String? validateOptionalVenueInput(String? value) =>
    cleanVenueInput(value ?? '').isEmpty ? null : validateVenueInput(value);

/// Sends a venue report to the server. Production uses
/// [MatchRepository.reportVenue]; widget tests pass a fake.
typedef VenueReporter = Future<void> Function({
  String? requestId,
  String? matchId,
  String? proposalId,
});

/// Confirms, then flags the venue name of a request, a match or a venue
/// suggested on a proposal for admin review. Pass exactly one of [requestId] /
/// [matchId] / [proposalId]. [report] is a test seam; leave it null in the app.
Future<void> reportVenueFlow(
  BuildContext context, {
  String? requestId,
  String? matchId,
  String? proposalId,
  VenueReporter? report,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: matchDialogColor(ctx),
      surfaceTintColor: Colors.transparent,
      shape: matchDialogShape(ctx),
      title: const Text('Report this venue name?'),
      content: const Text(
        'Use this if the venue name looks fake or inappropriate. '
        "We'll take a look.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Report'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await (report ?? MatchRepository().reportVenue)(
      requestId: requestId,
      matchId: matchId,
      proposalId: proposalId,
    );
    if (context.mounted) showSuccess(context, "Thanks, we'll review it");
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// What the proposing member chose in the "Propose this match?" dialog.
class ProposeChoice {
  /// The cleaned venue they would rather play at, or null to play at the
  /// request's own venue.
  final String? venueText;
  const ProposeChoice({this.venueText});
}

/// Confirms a proposal and lets the proposing member optionally type another
/// venue. Resolves to null when cancelled. [requestVenue] is the venue the
/// request already names (null for older requests that have none).
Future<ProposeChoice?> showProposeDialog(
  BuildContext context, {
  required String opponentName,
  required String city,
  String? requestVenue,
}) {
  return showDialog<ProposeChoice>(
    context: context,
    builder: (_) => _ProposeDialog(
      opponentName: opponentName,
      city: city,
      requestVenue: requestVenue,
    ),
  );
}

class _ProposeDialog extends StatefulWidget {
  final String opponentName;
  final String city;
  final String? requestVenue;
  const _ProposeDialog({
    required this.opponentName,
    required this.city,
    this.requestVenue,
  });

  @override
  State<_ProposeDialog> createState() => _ProposeDialogState();
}

class _ProposeDialogState extends State<_ProposeDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final venue = cleanVenueInput(_ctrl.text);
    Navigator.pop(context, ProposeChoice(venueText: venue.isEmpty ? null : venue));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.muted(context);
    final theirVenue = widget.requestVenue;
    final hasTheirVenue = theirVenue != null && theirVenue.isNotEmpty;
    return AlertDialog(
      // Title and content scroll together, so a small phone with large text
      // and the keyboard open never overflows; the buttons stay in view.
      scrollable: true,
      backgroundColor: matchDialogColor(context),
      surfaceTintColor: Colors.transparent,
      shape: matchDialogShape(context),
      title: const Text('Propose this match?'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Propose a match against ${widget.opponentName} in '
              '${widget.city}. Their captain reviews proposals and picks '
              "one — you'll be notified either way.",
            ),
            if (hasTheirVenue) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place_outlined,
                      size: 18, color: AppColors.brand(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Their venue: $theirVenue',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, height: 1.3),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _ctrl,
              maxLength: kVenueMaxLength,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: hasTheirVenue
                    ? 'Prefer a different venue? (optional)'
                    : 'Where would you like to play? (optional)',
                prefixIcon: const Icon(Icons.place_outlined),
              ),
              validator: validateOptionalVenueInput,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 4),
            Text(
              hasTheirVenue
                  ? 'Leave it empty to play at their venue. If you type one, '
                      'their captain can accept it or decline.'
                  : 'Their captain can accept your venue or decline.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: muted, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              kVenueDisclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.5, color: muted, height: 1.35),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Send Proposal')),
      ],
    );
  }
}

/// Confirms accepting a proposal. When the proposing team suggested a venue
/// ([venueText]) it is shown, because accepting makes it the match's venue;
/// the captain can decline instead to keep their own. Resolves to true only
/// when the captain taps Accept.
Future<bool?> showAcceptProposalDialog(
  BuildContext context, {
  required String teamName,
  String? venueText,
}) {
  final venue = cleanVenueInput(venueText ?? '');
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: const Text('Accept this proposal?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$teamName wants to play your match. Accepting confirms the '
              'match now and declines every other pending proposal on this '
              'request.'),
          if (venue.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined,
                    size: 18, color: AppColors.brand(ctx)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Venue: $venue',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, height: 1.3)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The match will be played here. Decline instead if you would '
              'rather keep your own venue.',
              style: Theme.of(ctx)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.muted(ctx), height: 1.4),
            ),
            const SizedBox(height: 6),
            Text(
              kVenueDisclaimer,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  fontSize: 11.5, color: AppColors.muted(ctx), height: 1.35),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept')),
      ],
    ),
  );
}

/// Asks the requesting captain for a new venue name. Resolves to the cleaned
/// text, or null when cancelled.
Future<String?> showEditVenueDialog(BuildContext context, {String? initial}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _EditVenueDialog(initial: initial),
  );
}

class _EditVenueDialog extends StatefulWidget {
  final String? initial;
  const _EditVenueDialog({this.initial});

  @override
  State<_EditVenueDialog> createState() => _EditVenueDialogState();
}

class _EditVenueDialogState extends State<_EditVenueDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, cleanVenueInput(_ctrl.text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      // Title and content scroll together, so a small phone with large text
      // and the keyboard open never overflows; the buttons stay in view.
      scrollable: true,
      backgroundColor: matchDialogColor(context),
      surfaceTintColor: Colors.transparent,
      shape: matchDialogShape(context),
      title: const Text('Change venue'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _ctrl,
              autofocus: true,
              maxLength: kVenueMaxLength,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Venue name',
                prefixIcon: Icon(Icons.place_outlined),
              ),
              validator: validateVenueInput,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Text(
              'The other captain gets a notification. Please call them to '
              'let them know about the change.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.muted(context), height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              kVenueDisclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  color: AppColors.muted(context),
                  height: 1.35),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// The request exactly as other captains will see it, shown while the captain
/// is still typing so the venue name is never a surprise. Uses the typed text
/// verbatim (whitespace tidied the way the server does).
class VenuePreviewCard extends StatelessWidget {
  final String venueText;

  /// Secondary line, e.g. "30/10/2026 · 19:00 · Nicosia".
  final String whenLabel;

  const VenuePreviewCard({
    super.key,
    required this.venueText,
    required this.whenLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typed = cleanVenueInput(venueText);
    final hasText = typed.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.chip(context),
        borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PREVIEW · WHAT OTHER CAPTAINS SEE',
              style: matchSectionLabelStyle(context)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place_outlined,
                  size: 20, color: AppColors.brand(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasText ? typed : 'Your venue name',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: hasText ? null : AppColors.muted(context),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 2),
            child: Text(
              whenLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.muted(context),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            kVenueDisclaimer,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              height: 1.35,
              color: AppColors.muted(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a confirmed match is played, exactly as the captain who opened the
/// request typed it. FootRank never shows names from its own courts list here.
///
/// The requesting captain decides the venue and can change it (e.g. when it
/// turns out to be full); the other captain is notified, can call them, and
/// can report a venue name that looks fake.
class VenueCard extends StatelessWidget {
  /// Null / empty means "not set yet".
  final String? venueText;

  /// Viewer is the captain who opened the request (the home side).
  final bool isRequester;
  final bool canEdit;
  final bool canReport;

  /// Label for the call button (e.g. "Call Andreas"), null hides it.
  final String? callLabel;
  final VoidCallback? onCall;
  final VoidCallback? onEdit;
  final VoidCallback? onReport;
  final VoidCallback? onDirections;

  const VenueCard({
    super.key,
    required this.venueText,
    required this.isRequester,
    required this.canEdit,
    required this.canReport,
    this.callLabel,
    this.onCall,
    this.onEdit,
    this.onReport,
    this.onDirections,
  });

  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback? onPressed,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(AppSemantic.minTapTarget),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: AppColors.brand(context)),
          label: Text(label),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final venue = venueText;
    final hasVenue = venue != null && venue.isNotEmpty;
    final muted = AppColors.muted(context);
    final hint = isRequester
        ? 'If the venue is full, you decide where to play. Update it here '
            'and give the other captain a call.'
        : 'If the venue turns out to be full, the other captain decides where '
            'to play and will let you know.';
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Venue',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.15,
                  ),
                ),
              ),
              if (canReport && hasVenue)
                IconButton(
                  tooltip: 'Report venue name',
                  icon: Icon(Icons.flag_outlined, size: 20, color: muted),
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: EdgeInsets.zero,
                  onPressed: onReport,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.place_outlined,
                  size: 20, color: AppColors.brand(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasVenue ? venue : 'Not set yet',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: hasVenue ? null : muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: TextStyle(fontSize: 13, height: 1.45, color: muted),
          ),
          const SizedBox(height: 4),
          Text(
            kVenueDisclaimer,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  height: 1.35,
                  color: muted,
                ),
          ),
          const SizedBox(height: 4),
          if (hasVenue && onDirections != null)
            _action(context, Icons.near_me_outlined, 'Get Directions',
                onDirections),
          if (canEdit)
            _action(context, Icons.edit_outlined, 'Change venue', onEdit),
          if (callLabel != null)
            _action(context, Icons.call_outlined, callLabel!, onCall),
        ],
      ),
    );
  }
}
