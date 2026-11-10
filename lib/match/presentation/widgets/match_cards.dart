import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/maps_launcher.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/app_button.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/core/widgets/segmented_tabs.dart';
import 'package:footrank/core/widgets/status_chip.dart';
import 'package:footrank/match/presentation/widgets/match_formatters.dart';
import 'package:footrank/match/presentation/widgets/match_team_avatar.dart';
import 'package:footrank/match/presentation/widgets/venue_widgets.dart';
import 'package:footrank/models/match_model.dart';
import 'package:footrank/models/match_proposal_model.dart';
import 'package:footrank/models/match_request_model.dart';
import 'package:footrank/models/match_status.dart';
import 'package:footrank/payment/data/payment_repository.dart';
import 'package:footrank/payment/presentation/widgets/pay_fee_button.dart';
import 'package:footrank/routing/app_router.dart';

// The cards of the Matches screen. They only call back -- none of them talks
// to the network -- so the page owns every action and each card can be tested
// on its own.
//
// One rhythm for all of them: who (avatar, name, Pitch Power) on top, then when
// and where, then what you can do. Pitch Power always carries its "PWR" label
// and, where it helps a decision, how far above or below you the team is.

/// The standard spacing and surface of a card in a Matches list.
class MatchCardFrame extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// Optional wash of a semantic colour (a won / lost match).
  final Color? tint;

  const MatchCardFrame({
    super.key,
    required this.child,
    this.onTap,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSemantic.screenPadding,
        vertical: AppSemantic.rowGap / 2,
      ),
      child: GlassCard(
        padding: const EdgeInsets.all(AppSemantic.cardPadding),
        onTap: onTap,
        tint: tint,
        child: child,
      ),
    );
  }
}

/// "1780 PWR", optionally followed by how that compares with your team
/// ("· 120 above you"). Never a bare number: an unlabeled "1770" next to a
/// team name reads as anything from a price to a jersey number.
class PowerLabel extends StatelessWidget {
  final int? value;
  final PowerGap? gap;
  final int maxLines;

  const PowerLabel({super.key, required this.value, this.gap, this.maxLines = 2});

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.muted(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value == null ? '–' : '$value',
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w800,
              color: AppColors.brand(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(
            text: ' PWR',
            style: TextStyle(color: muted, fontWeight: FontWeight.w700),
          ),
          if (gap != null)
            TextSpan(text: ' · ${gap!.label}', style: TextStyle(color: muted)),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

/// A small label pill (Ranked, Pending, WON). Same shape as [StatusChip] so
/// the two sit side by side as one family.
class MatchPill extends StatelessWidget {
  final String label;
  final Color color;
  const MatchPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSemantic.statusPillRadius),
      ),
      // A pill is a label, not reading text: it stops growing at 1.3x so it
      // never crowds the name beside it at large text sizes.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

/// An icon, then a line (or a few) of information. [trailing] sits at the end,
/// centred against the whole row (the venue report flag).
class _MetaRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final Widget child;
  final Widget? trailing;

  const _MetaRow({
    required this.icon,
    required this.child,
    this.iconColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final centered = trailing != null;
    return Row(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: centered ? 0 : AppSemantic.labelGap),
          child: Icon(
            icon,
            size: AppIconSize.sm,
            color: iconColor ?? AppColors.muted(context),
          ),
        ),
        const SizedBox(width: AppSemantic.iconGap),
        Expanded(child: child),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// The flag that reports a venue name a captain typed.
class _FlagButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _FlagButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Report venue name',
      icon: Icon(
        Icons.flag_outlined,
        size: AppIconSize.sm,
        color: AppColors.muted(context),
      ),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minWidth: AppSemantic.minTapTarget,
        minHeight: AppSemantic.minTapTarget,
      ),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}

/// A venue name a captain typed. The pin carries the accent colour; the name is
/// plain text in a firm weight, so a long free-text name never shouts. [lead]
/// ("Suggests:") is the muted lead-in when the venue is somebody's suggestion.
class _VenueText extends StatelessWidget {
  final String venue;
  final String? lead;
  final int? maxLines;

  const _VenueText(this.venue, {this.lead, this.maxLines});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontWeight: FontWeight.w700, height: 1.3);
    final overflow = maxLines == null ? null : TextOverflow.ellipsis;
    if (lead == null) {
      return Text(venue, maxLines: maxLines, overflow: overflow, style: style);
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$lead ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.muted(context),
            ),
          ),
          TextSpan(text: venue),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
      style: style,
    );
  }
}

/// The venue as the card's focal point: a tinted panel with a large pin and the
/// name in a bigger, heavier type, so the captain sees WHERE before anything
/// else. [trailing] (the report flag) sits at the end.
class _VenuePanel extends StatelessWidget {
  final String venue;
  final Widget? trailing;

  /// Opens the venue in Maps; shown as a button when the venue has a location.
  final VoidCallback? onMap;

  const _VenuePanel({required this.venue, this.trailing, this.onMap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = AppColors.brand(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.10),
        border: Border.all(color: brand.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: brand.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.stadium_outlined, size: 24, color: brand),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VENUE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.muted(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: AppSemantic.labelGap),
                Text(
                  venue,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (onMap != null)
            IconButton(
              tooltip: 'Open in Maps',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: EdgeInsets.zero,
              icon: Icon(Icons.map_outlined, color: brand),
              onPressed: onMap,
            ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A hairline that sets a footer line (a fee, a status) apart from the match
/// above it, with the card's rhythm on both sides.
class _FooterRule extends StatelessWidget {
  const _FooterRule();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Divider(height: AppSemantic.borderWidth),
    );
  }
}

/// The fee line of a confirmed match: what is owed and the button that pays it.
/// The button sits beside the message when both fit and drops underneath when
/// they do not (a narrow phone, a large text size), so the message is never
/// squeezed into a sliver.
class _FeeDue extends StatelessWidget {
  final PendingFee fee;
  final VoidCallback? onPaid;

  const _FeeDue({required this.fee, this.onPaid});

  @override
  Widget build(BuildContext context) {
    final failed = fee.previouslyFailed;
    // A Wrap only ever grows to its content, so it is given the full width
    // to push the button to the far end when the two share a line.
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_rounded,
                size: AppIconSize.sm,
                color: AppColors.muted(context),
              ),
              const SizedBox(width: AppSemantic.iconGap),
              Flexible(
                child: Text(
                  failed
                      ? 'Payment failed — your team is not covered'
                      : 'Team fee due',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: failed ? AppColors.dangerText(context) : null,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          PayFeeButton(fee: fee, compact: true, onPaid: onPaid),
        ],
      ),
    );
  }
}

/// A card action at the one height every pair of card buttons shares.
/// AppButton's primary is 52 tall and its secondary 48, which put "Reject" and
/// "Accept" side by side at two different heights; here both are 48.
class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool fullWidth;

  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSemantic.minTapTarget,
      child: AppButton(
        label: label,
        variant: variant,
        fullWidth: fullWidth,
        onPressed: onPressed,
      ),
    );
  }
}

/// A team shown upright: crest, name, Pitch Power (and record).
class _TeamColumn extends StatelessWidget {
  final String name;
  final String? logo;
  final int? rating;
  final String? record;

  const _TeamColumn({
    required this.name,
    required this.logo,
    required this.rating,
    this.record,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MatchTeamAvatar(name: name, imageUrl: logo, radius: 24),
        const SizedBox(height: AppSpacing.xs),
        Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
        ),
        const SizedBox(height: AppSpacing.xxs),
        PowerLabel(value: rating, maxLines: 1),
        if (record != null) ...[
          const SizedBox(height: AppSemantic.labelGap),
          Text(
            record!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.muted(context)),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Opponents: open requests from other teams
// ---------------------------------------------------------------------------

/// An open request from another team, with one action: propose a match.
class OpponentCard extends StatelessWidget {
  final MatchRequestModel opponent;

  /// The acting team's Pitch Power, for the "above / below you" note.
  final int? myRating;
  final VoidCallback onPropose;

  const OpponentCard({
    super.key,
    required this.opponent,
    required this.onPropose,
    this.myRating,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gap = PowerGap.between(mine: myRating, theirs: opponent.teamRating);
    final venue = opponent.venueText;
    return MatchCardFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MatchTeamAvatar(
                name: opponent.teamName ?? '?',
                imageUrl: opponent.teamLogo,
                radius: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      opponent.teamName ?? 'Unknown team',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSemantic.labelGap),
                    PowerLabel(value: opponent.teamRating, gap: gap),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              MatchPill(
                label: matchTypeLabel(opponent.matchType),
                color: opponent.isRanked
                    ? AppColors.brand(context)
                    : AppColors.muted(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _MetaRow(
            icon: Icons.event_outlined,
            child: Text(
              '${formatMatchWhen(opponent.scheduledAt)} · ${opponent.format}',
              style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800, fontFamily: AppFonts.display),
            ),
          ),
          if (venue != null && venue.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _VenuePanel(
              venue: venue,
              onMap: opponent.venueLocation == null
                  ? null
                  : () => openVenueInMaps(
                        name: venue,
                        city: opponent.city,
                        location: opponent.venueLocation,
                      ),
              trailing: _FlagButton(
                onPressed: () =>
                    reportVenueFlow(context, requestId: opponent.id),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _ActionButton(
            label: 'Propose Match',
            variant: AppButtonVariant.secondary,
            onPressed: onPropose,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity: my requests, what I sent, what waits for confirmation
// ---------------------------------------------------------------------------

/// A request the acting team posted, with the proposals it received (and the
/// venue each one suggests).
class RequestCard extends StatelessWidget {
  final MatchRequestModel request;
  final VoidCallback? onCancel;
  final VoidCallback? onInvite;
  final List<MatchProposalModel> proposals;
  final ValueChanged<MatchProposalModel>? onAcceptProposal;
  final ValueChanged<MatchProposalModel>? onRejectProposal;

  /// Test seam for the "Report venue name" flag on a suggested venue.
  /// Production leaves it null and the real repository is used.
  @visibleForTesting
  final VenueReporter? reportVenue;

  const RequestCard({
    super.key,
    required this.request,
    this.onCancel,
    this.onInvite,
    this.proposals = const [],
    this.onAcceptProposal,
    this.onRejectProposal,
    this.reportVenue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.muted(context);
    final venue = request.venueText;
    return MatchCardFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatMatchWhen(request.scheduledAt),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFamily: AppFonts.display,
                      ),
                    ),
                    const SizedBox(height: AppSemantic.labelGap),
                    Text(
                      '${request.city} · ${request.format}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              if (onInvite != null)
                IconButton(
                  tooltip: 'Invite a rival team',
                  icon: const Icon(Icons.share_outlined),
                  color: AppColors.brand(context),
                  onPressed: onInvite,
                ),
              if (onCancel != null)
                IconButton(
                  tooltip: 'Cancel request',
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.dangerText(context),
                  onPressed: onCancel,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MatchPill(
                label: matchTypeLabel(request.matchType),
                color: request.isRanked ? AppColors.brand(context) : muted,
              ),
              StatusChip(status: MatchStatus.fromString(request.status)),
            ],
          ),
          if (venue != null && venue.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _VenuePanel(
              venue: venue,
              onMap: request.venueLocation == null
                  ? null
                  : () => openVenueInMaps(
                        name: venue,
                        city: request.city,
                        location: request.venueLocation,
                      ),
            ),
          ],
          // Proposals ease in when they arrive after the card is already on
          // screen, instead of shoving everything below down in one frame.
          MotionSize(
            child: proposals.isEmpty
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.md),
                      const Divider(height: AppSemantic.borderWidth),
                      const SizedBox(height: AppSpacing.md),
                      // A Wrap, not a Row: at the largest text sizes on a
                      // narrow phone the count drops under the word instead
                      // of running off the card.
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'PROPOSALS',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                          CountBadge(count: proposals.length),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final p in proposals)
                        _ProposalTile(
                          proposal: p,
                          myRating: request.teamRating,
                          onAccept: onAcceptProposal,
                          onReject: onRejectProposal,
                          reportVenue: reportVenue,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One proposal on a request: who, how strong, the venue they suggest, and the
/// two decisions.
class _ProposalTile extends StatelessWidget {
  final MatchProposalModel proposal;
  final int? myRating;
  final ValueChanged<MatchProposalModel>? onAccept;
  final ValueChanged<MatchProposalModel>? onReject;
  final VenueReporter? reportVenue;

  const _ProposalTile({
    required this.proposal,
    required this.myRating,
    required this.onAccept,
    required this.onReject,
    required this.reportVenue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = proposal;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
        border: Border.all(color: AppColors.border(context)),
        borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MatchTeamAvatar(
                name: p.teamName ?? '?',
                imageUrl: p.teamLogo,
                radius: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.teamName ?? 'Unknown team',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSemantic.labelGap),
                    PowerLabel(
                      value: p.teamRating,
                      gap: PowerGap.between(mine: myRating, theirs: p.teamRating),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (p.hasVenueSuggestion) ...[
            const SizedBox(height: AppSpacing.xs),
            _MetaRow(
              icon: Icons.place_outlined,
              iconColor: AppColors.brand(context),
              trailing: _FlagButton(
                onPressed: () => reportVenueFlow(
                  context,
                  proposalId: p.id,
                  report: reportVenue,
                ),
              ),
              child: _VenueText(p.venueText!, lead: 'Suggests:'),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Reject',
                  variant: AppButtonVariant.secondary,
                  onPressed: onReject == null ? null : () => onReject!(p),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _ActionButton(
                  label: 'Accept',
                  onPressed: onAccept == null ? null : () => onAccept!(p),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One proposal the acting team has sent, so any team member can see what is
/// outstanding -- not just the person who sent it. Read-only: only the target
/// request's own captain can act on it.
class SentProposalCard extends StatelessWidget {
  final MatchProposalModel proposal;

  /// The acting team's Pitch Power, for the "above / below you" note.
  final int? myRating;

  const SentProposalCard({super.key, required this.proposal, this.myRating});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = proposal.requestScheduledAt;
    final details = [
      if (proposal.requestCity != null) proposal.requestCity!,
      if (proposal.requestMatchType != null)
        matchTypeLabel(proposal.requestMatchType!),
      if (proposal.requestFormat != null) proposal.requestFormat!,
    ].join(' · ');
    return MatchCardFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MatchTeamAvatar(
                name: proposal.targetTeamName ?? '?',
                imageUrl: proposal.targetTeamLogo,
                radius: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proposal.targetTeamName ?? 'Unknown team',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (proposal.targetTeamRating != null) ...[
                      const SizedBox(height: AppSemantic.labelGap),
                      PowerLabel(
                        value: proposal.targetTeamRating,
                        gap: PowerGap.between(
                          mine: myRating,
                          theirs: proposal.targetTeamRating,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              MatchPill(label: 'Pending', color: AppColors.muted(context)),
            ],
          ),
          if (when != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _MetaRow(
              icon: Icons.event_outlined,
              child: Text(
                formatMatchWhen(when),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
          if (proposal.hasVenueSuggestion) ...[
            const SizedBox(height: AppSpacing.xs),
            _MetaRow(
              icon: Icons.place_outlined,
              iconColor: AppColors.brand(context),
              child: _VenueText(
                proposal.venueText!,
                lead: 'You suggested:',
                maxLines: 2,
              ),
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              details,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.muted(context)),
            ),
          ],
        ],
      ),
    );
  }
}

/// A fixture both captains still have to confirm.
class PendingMatchCard extends StatelessWidget {
  final MatchModel match;
  final bool iConfirmed;
  final bool canAct;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const PendingMatchCard({
    super.key,
    required this.match,
    required this.iConfirmed,
    required this.canAct,
    required this.onConfirm,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final venue = match.venueText;
    return MatchCardFrame(
      onTap: () => context.push(AppRoutes.matchDetail, extra: match.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatMatchWhen(match.scheduledAt),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              MatchPill(label: 'Pending', color: AppColors.muted(context)),
            ],
          ),
          const SizedBox(height: AppSemantic.labelGap),
          Text(
            '${match.city} · ${matchTypeLabel(match.matchType)} · ${match.format}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.muted(context)),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TeamColumn(
                  name: match.homeTeamName ?? 'Home',
                  logo: match.homeTeamLogo,
                  rating: match.homeTeamRating,
                  record: match.homeTeamRecord,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'vs',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.muted(context),
                  ),
                ),
              ),
              Expanded(
                child: _TeamColumn(
                  name: match.awayTeamName ?? 'Away',
                  logo: match.awayTeamLogo,
                  rating: match.awayTeamRating,
                  record: match.awayTeamRecord,
                ),
              ),
            ],
          ),
          if (venue != null && venue.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _MetaRow(
              icon: Icons.place_outlined,
              iconColor: AppColors.brand(context),
              child: _VenueText(venue),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (!canAct)
            Text(
              'Only your captain can confirm or reject',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.muted(context)),
            )
          else ...[
            if (iConfirmed) ...[
              Text(
                'You have confirmed. Waiting for the other captain.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.muted(context)),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            // Side by side at one height; once you have confirmed only the way
            // out is left, and it keeps to its own width.
            if (iConfirmed)
              Align(
                alignment: Alignment.centerLeft,
                child: _ActionButton(
                  label: 'Reject',
                  variant: AppButtonVariant.secondary,
                  fullWidth: false,
                  onPressed: onReject,
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Reject',
                      variant: AppButtonVariant.secondary,
                      onPressed: onReject,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _ActionButton(
                      label: 'Confirm',
                      onPressed: onConfirm,
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fixtures: confirmed and played matches
// ---------------------------------------------------------------------------

class MatchCard extends StatelessWidget {
  final MatchModel match;
  final String? myTeamId;

  /// Set only when the signed-in captain owes this match's fee -- its presence
  /// is what authorises the Pay button, so no separate captain check is needed.
  final PendingFee? pendingFee;
  final VoidCallback? onPaid;

  const MatchCard({
    super.key,
    required this.match,
    this.myTeamId,
    this.pendingFee,
    this.onPaid,
  });

  /// 'win' | 'loss' | 'draw' for my team, or null if not a finished match.
  String? get _result {
    if (match.status != 'completed' ||
        match.homeScore == null ||
        match.awayScore == null ||
        myTeamId == null) {
      return null;
    }
    final iAmHome = match.homeTeamId == myTeamId;
    final mine = iAmHome ? match.homeScore! : match.awayScore!;
    final theirs = iAmHome ? match.awayScore! : match.homeScore!;
    if (mine > theirs) return 'win';
    if (mine < theirs) return 'loss';
    return 'draw';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.muted(context);
    final (Color? accent, String? resultLabel) = switch (_result) {
      'win' => (AppColors.success, 'WON'),
      'loss' => (AppColors.danger, 'LOST'),
      'draw' => (AppColors.silver, 'DRAW'),
      _ => (null, null),
    };
    final centre = match.hasScore
        ? '${match.homeScore} – ${match.awayScore}'
        : 'vs';
    final statusLabel = matchStatusLabel(
      MatchStatus.fromString(match.status),
      paymentStatus: match.paymentStatus,
      paymentsEnabled: PaymentRepository.isEnabled,
    );
    return MatchCardFrame(
      tint: accent,
      onTap: () => context.push(AppRoutes.matchDetail, extra: match.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatMatchWhen(match.scheduledAt),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (resultLabel != null)
                MatchPill(label: resultLabel, color: accent!)
              else
                MatchPill(label: statusLabel, color: AppColors.brand(context)),
            ],
          ),
          const SizedBox(height: AppSemantic.labelGap),
          Text(
            '${match.city} · ${matchTypeLabel(match.matchType)} · ${match.format}',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TeamColumn(
                  name: match.homeTeamName ?? 'Home',
                  logo: match.homeTeamLogo,
                  rating: match.homeTeamRating,
                  record: match.homeTeamRecord,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  centre,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: match.hasScore
                        ? AppTypeScale.headline2
                        : AppTypeScale.title3,
                    fontWeight: FontWeight.w800,
                    color: match.hasScore ? theme.colorScheme.onSurface : muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: _TeamColumn(
                  name: match.awayTeamName ?? 'Away',
                  logo: match.awayTeamLogo,
                  rating: match.awayTeamRating,
                  record: match.awayTeamRecord,
                ),
              ),
            ],
          ),
          // The fee, payable right here: captains used to have to open the
          // match and scroll to find out one was owed at all. It sits under a
          // hairline as the card's footer.
          if (pendingFee != null) ...[
            const _FooterRule(),
            _FeeDue(fee: pendingFee!, onPaid: onPaid),
          ] else if (match.status == 'confirmed' &&
              PaymentRepository.isEnabled &&
              match.paymentStatus != 'paid') ...[
            // Nothing owed by me, but the match isn't settled: the other team
            // (or my captain) still has to pay.
            const _FooterRule(),
            Row(
              children: [
                Icon(Icons.hourglass_top_rounded,
                    size: AppIconSize.sm, color: muted),
                const SizedBox(width: AppSemantic.iconGap),
                Expanded(
                  child: Text(
                    'Match is secured once both teams have paid',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

/// Placeholder with the outline of a card, shown instead of a spinner so the
/// page keeps its shape while the data arrives.
class MatchCardSkeleton extends StatelessWidget {
  const MatchCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: MatchCardFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ShimmerBox(width: 44, height: 44, radius: AppSemantic.pill),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(
                          width: double.infinity, height: 14, radius: AppRadius.sm),
                      SizedBox(height: AppSpacing.xs),
                      ShimmerBox(width: 110, height: 12, radius: AppRadius.sm),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.md),
            ShimmerBox(width: 190, height: 14, radius: AppRadius.sm),
            SizedBox(height: AppSpacing.xs),
            ShimmerBox(width: 150, height: 14, radius: AppRadius.sm),
          ],
        ),
      ),
    );
  }
}

/// A few skeleton cards.
class MatchListSkeleton extends StatelessWidget {
  final int count;
  const MatchListSkeleton({super.key, this.count = 2});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) const MatchCardSkeleton(),
      ],
    );
  }
}
