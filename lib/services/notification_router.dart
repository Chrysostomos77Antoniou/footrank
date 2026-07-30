import 'package:footrank/core/app_refresh.dart';
import 'package:footrank/routing/app_router.dart';

// Notification types backed by a `matches` row -- deep-link straight to the
// match's own detail page.
const _matchTypes = {
  'match_accepted',
  'match_reminder',
  'court_suggested',
  'match_expired',
};

// Notification types backed by a `match_requests` row -- there's no single-
// request detail page, so the closest useful destination is the Matches
// tab (My Activity), where that request and its proposals are shown.
const _requestTypes = {
  'match_request',
  'match_proposal',
  'match_proposal_declined',
  'match_request_stale',
  'match_cancelled',
};

/// Routes a tapped notification (push banner, cold-start launch, or an item
/// in the in-app list) to whatever it was actually about, and forces a fresh
/// fetch first so the destination reflects the change being reported instead
/// of a stale cache -- e.g. tapping "X accepted your match request" syncs
/// then takes you straight to that now-confirmed match.
void handleNotificationTap({String? type, String? referenceId}) {
  triggerAppRefresh();

  if (type == null || referenceId == null) {
    appRouter.push(AppRoutes.notifications);
    return;
  }

  if (_matchTypes.contains(type)) {
    appRouter.push(AppRoutes.matchDetail, extra: referenceId);
  } else if (_requestTypes.contains(type)) {
    appRouter.go(AppRoutes.matches);
  } else if (type == 'player_invite') {
    appRouter.push(AppRoutes.invitations);
  } else if (type == 'team_recruitment') {
    appRouter.go(AppRoutes.team);
  } else {
    appRouter.push(AppRoutes.notifications);
  }
}
