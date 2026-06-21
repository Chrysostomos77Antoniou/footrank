import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:footrank/auth/data/auth_repository.dart';
import 'package:footrank/auth/presentation/pages/login_page.dart';
import 'package:footrank/auth/presentation/pages/register_page.dart';
import 'package:footrank/core/presentation/pages/home_shell_page.dart';
import 'package:footrank/free_agents/presentation/pages/free_agents_page.dart';
import 'package:footrank/home/presentation/pages/home_page.dart';
import 'package:footrank/notifications/presentation/pages/notifications_page.dart';
import 'package:footrank/onboarding/onboarding_prefs.dart';
import 'package:footrank/onboarding/presentation/pages/onboarding_page.dart';
import 'package:footrank/match/presentation/pages/create_match_request_page.dart';
import 'package:footrank/match/presentation/pages/match_detail_page.dart';
import 'package:footrank/match/presentation/pages/match_discovery_page.dart';
import 'package:footrank/match/presentation/pages/matches_page.dart';
import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/profile/presentation/pages/edit_profile_page.dart';
import 'package:footrank/profile/presentation/pages/profile_page.dart';
import 'package:footrank/models/user_model.dart';
import 'package:footrank/rankings/presentation/pages/rankings_page.dart';
import 'package:footrank/profile/presentation/pages/profile_setup_page.dart';
import 'package:footrank/routing/router_refresh_stream.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/team/presentation/pages/create_team_page.dart';
import 'package:footrank/team/presentation/pages/edit_team_page.dart';
import 'package:footrank/team/presentation/pages/invitations_page.dart';
import 'package:footrank/team/presentation/pages/join_team_page.dart';
import 'package:footrank/team/presentation/pages/team_page.dart';

class AppRoutes {
  static const login = '/login';
  static const register = '/register';
  static const profileSetup = '/profile-setup';
  static const home = '/';
  static const team = '/team';
  static const createTeam = '/team/create';
  static const editTeam = '/team/edit';
  static const joinTeam = '/team/join';
  static const teamRankings = '/rankings';
  static const matches = '/matches';
  static const createMatch = '/matches/create';
  static const discoverMatches = '/matches/discover';
  static const matchDetail = '/matches/detail';
  static const profile = '/profile';
  static const editProfile = '/profile/edit';
  static const freeAgents = '/free-agents';
  static const invitations = '/invitations';
  static const notifications = '/notifications';
  static const onboarding = '/onboarding';
}

final _authRepo = AuthRepository();
final _profileRepo = ProfileRepository();

/// A slide-up + fade transition for pushed pages.
CustomTransitionPage<T> _animatedPage<T>(Widget child, GoRouterState state) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

GoRouter buildRouter() => GoRouter(
      initialLocation: AppRoutes.home,
      redirect: (context, state) async {
        final isLoggedIn = _authRepo.currentUser != null;
        final loc = state.matchedLocation;

        // First run: show onboarding before anything else (only when logged out).
        if (!OnboardingPrefs.seen && !isLoggedIn) {
          return loc == AppRoutes.onboarding ? null : AppRoutes.onboarding;
        }

        final isAuthRoute =
            loc == AppRoutes.login || loc == AppRoutes.register;
        final isSetupRoute = loc == AppRoutes.profileSetup;

        // Not logged in: only auth routes are allowed.
        if (!isLoggedIn) {
          ProfileRepository.invalidateCache();
          return isAuthRoute ? null : AppRoutes.login;
        }

        // Logged in: ensure a profile row exists before entering the app.
        // If the check fails (e.g. no internet), let the app proceed so the
        // screens can show graceful errors instead of a blank route.
        bool hasProfile;
        try {
          hasProfile = await _profileRepo
              .hasProfile()
              .timeout(const Duration(seconds: 6));
        } catch (_) {
          // Network slow/unavailable: don't block the app on a blank route.
          return isAuthRoute ? AppRoutes.home : null;
        }
        if (!hasProfile) {
          return isSetupRoute ? null : AppRoutes.profileSetup;
        }

        // Has a profile: keep them out of auth/setup screens.
        if (isAuthRoute || isSetupRoute) return AppRoutes.home;
        return null;
      },
      refreshListenable: RouterRefreshStream(
        Supabase.instance.client.auth.onAuthStateChange,
      ),
      routes: [
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (context, state) => const OnboardingPage(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: AppRoutes.register,
          builder: (context, state) => const RegisterPage(),
        ),
        GoRoute(
          path: AppRoutes.profileSetup,
          pageBuilder: (context, state) =>
              _animatedPage(const ProfileSetupPage(), state),
        ),
        GoRoute(
          path: AppRoutes.createTeam,
          pageBuilder: (context, state) =>
              _animatedPage(const CreateTeamPage(), state),
        ),
        GoRoute(
          path: AppRoutes.editTeam,
          pageBuilder: (context, state) =>
              _animatedPage(EditTeamPage(team: state.extra! as TeamModel), state),
        ),
        GoRoute(
          path: AppRoutes.joinTeam,
          pageBuilder: (context, state) =>
              _animatedPage(const JoinTeamPage(), state),
        ),
        GoRoute(
          path: AppRoutes.freeAgents,
          pageBuilder: (context, state) =>
              _animatedPage(const FreeAgentsPage(), state),
        ),
        GoRoute(
          path: AppRoutes.invitations,
          pageBuilder: (context, state) =>
              _animatedPage(const InvitationsPage(), state),
        ),
        GoRoute(
          path: AppRoutes.notifications,
          pageBuilder: (context, state) =>
              _animatedPage(const NotificationsPage(), state),
        ),
        GoRoute(
          path: AppRoutes.editProfile,
          pageBuilder: (context, state) =>
              _animatedPage(EditProfilePage(user: state.extra! as UserModel), state),
        ),
        GoRoute(
          path: AppRoutes.createMatch,
          pageBuilder: (context, state) => _animatedPage(
              CreateMatchRequestPage(teamId: state.extra! as String), state),
        ),
        GoRoute(
          path: AppRoutes.discoverMatches,
          pageBuilder: (context, state) => _animatedPage(
              MatchDiscoveryPage(teamId: state.extra! as String), state),
        ),
        GoRoute(
          path: AppRoutes.matchDetail,
          pageBuilder: (context, state) => _animatedPage(
              MatchDetailPage(matchId: state.extra! as String), state),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              HomeShellPage(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomePage(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppRoutes.team,
                builder: (context, state) => const TeamPage(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppRoutes.teamRankings,
                builder: (context, state) => const RankingsPage(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppRoutes.matches,
                builder: (context, state) => const MatchesPage(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfilePage(),
              ),
            ]),
          ],
        ),
      ],
    );
