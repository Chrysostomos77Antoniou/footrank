# FootRank — Architecture Overview

Orientation doc for a coding agent joining this repo cold. Written to be read
top-to-bottom before touching code. Paths are repo-relative.

---

## 1. What the app is

FootRank is a **Flutter mobile app for organizing amateur 5-a-side football
matches** (launch market: Cyprus). Users create a profile, form or join a team,
post a match request for a city/date/court, receive proposals from other teams,
play, then both captains confirm the score. Results move an **ELO rating** for
players and a team rating branded **"Pitch Power" (PWR)**, which feeds public
leaderboards.

Secondary surfaces:
- **Admin web panel** — a second Flutter *web* build target from the same
  codebase, for moderation (disputes, courts, flagged users).
- **Marketing/legal statics** — `docs/*.html` plus marketing playbooks in `docs/`.

Domain vocabulary you'll see in code:

| Term | Meaning |
|---|---|
| **Pitch Power / PWR** | Team rating (`teams.rating`), starts at 1500 |
| **ELO** | Individual player rating (`users.elo`), starts at 1500 |
| **Match request** | A team's open "we want a game" post (`match_requests`) |
| **Proposal** | Another team offering to play that request (`match_request_proposals`) |
| **Match** | A confirmed fixture (`matches`) |
| **Court** | A pitch/venue, admin-curated (`courts`) |
| **Free agent** | A player looking for a team |
| **Reliability / behavior** | Per-user sportsmanship counters fed by post-match ratings |

---

## 2. Stack

- **Flutter** (Dart SDK `^3.8.1`, CI pins Flutter **3.32.6**), Material 3.
- **Supabase** (`supabase_flutter`) — Postgres + Auth + Storage + Realtime.
  This is the *entire* backend. There is no custom API server in this repo.
- **Firebase** — Cloud Messaging (push), Crashlytics. Firebase Hosting serves
  the admin web build (`firebase.json`, hosting target `admin`).
- **go_router** — declarative routing with a `StatefulShellRoute` tab shell.
- **Auth providers** — email/password, Google, Apple, Facebook.
- Other: `shared_preferences`, `image_picker`, `video_player`,
  `cached_network_image`, `url_launcher`, `flutter_local_notifications`.

> **Note:** `flutter_riverpod` / `riverpod_annotation` / `riverpod_generator` are
> declared in `pubspec.yaml` but **not used anywhere** in `lib/`. There is no
> `ProviderScope`. Do not assume Riverpod idioms; see §5 for the real pattern.

---

## 3. Entry points and build targets

| Target | Entry | Command |
|---|---|---|
| Mobile app | `lib/main.dart` → `lib/app.dart` (`FootRankApp`) | `flutter run` |
| Admin panel | `lib/admin_main.dart` → `lib/admin/app.dart` (`AdminApp`) | `flutter build web -t lib/admin_main.dart` |

`lib/main.dart` startup order is deliberate and load-bearing (comments in the
file explain each step — read them before reordering):

1. Android system photo picker opt-in.
2. `themeController.load()`, `OnboardingPrefs.load()` (SharedPreferences).
3. `SupabaseService.initialize()`.
4. `initPasswordRecoveryListener()` — watches for the recovery deep link.
5. `FcmTokenService.initAuthListener()` — **must** be registered right after
   Supabase init; Supabase fires `initialSession` synchronously on a broadcast
   stream with no replay, so subscribing later permanently misses session
   restores.
6. Firebase init + Crashlytics error hooks + `NotificationService.initialize()`
   + `FcmTokenService.initTokenRefreshListener()` + one explicit token sync —
   all wrapped in try/catch so push failures never block launch.

`FootRankApp` is a `MaterialApp.router` that: rebuilds on `themeController`,
clamps text scale to 0.85–1.3, stacks a branded video splash
(`VideoSplashOverlay`) above the booting app, and handles cold-start
notification taps after the first frame.

The admin app is intentionally stripped: no Firebase, no push, no splash, no
onboarding, dark theme only, `home: AdminShell()` (no go_router).

---

## 4. Directory layout

Feature-first, with a `data/` + `presentation/` split inside each feature:

```
lib/
  main.dart / app.dart              mobile entry + root widget
  admin_main.dart                   admin web entry
  firebase_options.dart             generated
  models/                           ALL shared domain models (flat, not per-feature)
  services/                         cross-cutting singletons/statics
    supabase_service.dart           SupabaseClient accessor + init
    elo_engine.dart                 pure rating math (client-side mirror)
    notification_service.dart       FCM + local notifications
    fcm_token_service.dart          device-token sync into `fcm_tokens`
    notification_router.dart        notification type -> route mapping
  routing/
    app_router.dart                 routes, redirect guard, page transitions
    router_refresh_stream.dart      Stream -> Listenable adapter for go_router
  core/
    constants/                      AppConstants (dart-define config), cities
    theme/                          app_colors, app_theme, app_tokens, theme_controller
    widgets/                        shared component library (see §8)
    utils/                          motion, error_text, emojis, maps_launcher, password_strength
    presentation/pages/home_shell_page.dart   bottom-tab shell
    app_refresh.dart                global refresh/repaint signals
    services/gallery_picker.dart
  auth/  onboarding/  profile/  team/  match/  rankings/  free_agents/
  notifications/  home/            feature modules
  admin/                            admin-only app, repository, pages, widgets
```

Feature module shape (e.g. `match/`):

```
match/
  data/match_repository.dart        all Supabase calls for the feature
  data/court_repository.dart
  presentation/pages/*.dart         screens
  presentation/widgets/*.dart       feature-local widgets
```

**Rule of thumb:** models are shared and flat in `lib/models/`; data access
lives only in `*/data/*_repository.dart`; pages never talk to Supabase directly.

---

## 5. State management (important — it is not what you'd guess)

There is **no** Riverpod/BLoC/Provider graph. The pattern is:

- **`StatefulWidget` + `setState` + `FutureBuilder`** per screen (~37 stateful
  widgets across `lib/`).
- **Repositories are plain classes**, instantiated directly where needed (often
  `final _repo = MatchRepository();` as a field or a top-level `final`).
- **Two global `ValueNotifier<int>` signals** in `lib/core/app_refresh.dart`:
  - `appRefresh` / `triggerAppRefresh()` — "re-fetch from the server"; the Sync
    button and notification taps bump it, every tab listens and re-fetches.
  - `uiRepaint` / `triggerUiRepaint()` — "rebuild widgets only", bumped on tab
    switch; keeps loaded futures.
- **`themeController`** (`core/theme/theme_controller.dart`) is a
  `ChangeNotifier`-style singleton the root `AnimatedBuilder` listens to.
- One deliberate **static cache**: `ProfileRepository._cachedHasProfile`,
  invalidated via `ProfileRepository.invalidateCache()` on sign-out.
- **Realtime** is used in exactly one place: `NotificationRepository
  .subscribeToNew()` opens a Postgres-changes channel filtered to the user's
  own rows so the badge updates instantly.

When adding a screen, follow this pattern rather than introducing a new state
library.

---

## 6. Routing and auth gating

`lib/routing/app_router.dart` exposes `AppRoutes` (string constants) and a
single shared `appRouter` instance (`final GoRouter appRouter = buildRouter();`).
It is a global on purpose: notification taps fire outside the widget tree and
need to navigate without a `BuildContext`. **Never call `buildRouter()` a
second time** — two routers would keep divergent redirect state.

The `redirect` guard, in priority order:

1. `passwordRecovery` flag set (recovery deep link) → pin to `/reset-password`.
2. First run and logged out → `/onboarding`.
3. Logged out → only `/login`, `/register` allowed; everything else → `/login`.
4. Logged in but no `users` row → `/profile-setup` (with a 6s timeout; on
   network failure it lets the app through so screens can show real errors
   instead of a blank route).
5. Logged in with a profile → bounce away from auth/setup routes.

`refreshListenable` merges the Supabase `onAuthStateChange` stream (via
`RouterRefreshStream`) with the `passwordRecovery` notifier.

Shell: `StatefulShellRoute.indexedStack` with **5 branches** — `/` (Home),
`/team`, `/rankings`, `/matches`, `/profile` — rendered by `HomeShellPage`.
Everything else is a pushed route using `_animatedPage`, which applies the
shared fade+slide transition (durations/curves from `AppMotion`) and wraps the
page in `_SwipeBackWrapper` (velocity-based horizontal swipe-to-pop).

---

## 7. Backend contract (Supabase)

Config comes from `--dart-define` at build time; `AppConstants` ships
non-secret localhost placeholders so tests compile. Never commit real values.

```
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

**Tables read/written from the client:** `users`, `teams`, `team_members`,
`team_join_requests`, `team_invitations`, `match_requests`,
`match_request_proposals`, `matches`, `match_players`, `courts`,
`match_request_court_picks`, `behavior_reports`, `notifications`, `fcm_tokens`,
`user_contacts`, `push_debug_log`.

**Storage buckets:** `avatars` (user + team logos), `court-photos` (admin
writes only, enforced by Storage RLS).

**Postgres RPCs the client calls** — every multi-row or trust-sensitive
mutation is a server-side function, not client logic. This is the real
authorization boundary; RLS plus `is_admin` checks live in the database (which
is **not** in this repo — schema/migrations are managed in Supabase):

*Teams:* `create_team_atomic`, `leave_team`, `disband_team`,
`transfer_captaincy`, `accept_invitation_atomic`,
`approve_join_request_atomic`, `team_captain_contact`,
`preview_team_rating_delta`

*Matchmaking:* `propose_match`, `accept_match_proposal`,
`reject_match_proposal`, `accept_match_request`, `confirm_fixture`,
`cancel_match`, `cancel_confirmed_match`, `match_captain_contacts`

*Scoring:* `submit_match_score`, `confirm_match_score`

*Profile:* `create_profile_with_phone`, `update_my_phone`, `delete_my_account`

*Admin (all `is_admin`-gated server-side):* `admin_upsert_court`,
`admin_resolve_dispute`, `admin_force_cancel_match`,
`admin_set_user_moderation`, `admin_fetch_match_cancellations`

Push notifications are sent by a Supabase **Edge Function (`send-push`)** that
reads `fcm_tokens` — also outside this repo.

---

## 8. Core domain logic

### Match lifecycle
`lib/models/match_status.dart` encodes the state machine with a validated
transition table:

```
searching -> pending -> confirmed -> completed
```

`searching`/`pending` live on `match_requests`; `confirmed`/`completed` on
`matches`.

Flow in practice (`match/data/match_repository.dart`):

1. Captain creates a request (city, `scheduled_at`, `match_type`
   casual|ranked, `format` 5v5, one chosen court).
   `findSchedulingConflict()` mirrors the server's
   `enforce_no_overlapping_team_commitment()` guard (±1h window) so the UI can
   reject with a friendly message first.
2. Other teams browse `fetchCityRequests()` (filters: city, court, date,
   time-of-day ±60min, match type; hides past requests and any request this
   team already has a pending proposal on).
3. **Any team member** may `proposeMatch()`; only the requesting **captain**
   may `acceptProposal()` / `rejectProposal()`. Accepting creates the match and
   auto-cancels sibling proposals server-side.
4. Both captains `confirmFixture()`; captains mark per-player attendance
   (`markAttendance()`, upsert on `match_id,user_id`, min 5 attended per team
   enforced on submit and in the DB).
5. Each captain `submitScore()` → returns `'completed'` (agreement),
   `'disputed'` (opposite winners), or `'awaiting_opponent'`.
   `confirmScore()` closes it out. Disputes escalate to the admin panel.
6. Post-match sportsmanship: `submitBehavior()` writes `good`/`bad` (+reason)
   into `behavior_reports`, feeding `users.behavior_positive/negative` and the
   `behaviorLabel` getter on `UserModel`.

Cancellation: free until 2h before kick-off; from then on
`cancel_confirmed_match` docks the cancelling team **200 PWR** and returns
`{penalized: bool}`. The opponent's slot is reopened either way.

### Rating
`lib/services/elo_engine.dart` is pure, dependency-free, and unit-tested
(`test/elo_engine_test.dart`):

- Start 1500; K = **20 casual**, **40 ranked**.
- `teamRating()` = mean ELO of *attended* players only.
- Standard logistic `expectedScore()`, plus `newRating()` / `delta()`.

This is the **client-side mirror** of the DB trigger that actually persists
ratings on completion — the authoritative calculation (including a hidden
catch-up bonus, exposed only as deltas via `preview_team_rating_delta`) is
server-side. Keep the two in sync if you change either.

### Rankings
`rankings/data/ranking_repository.dart`: players need `matches_played >= 2`
(`RankingRepository.minMatches`) to appear, ordered by ELO desc, optional
position filter; teams ordered by rating desc, excluding
`disbanded_at IS NOT NULL`, optional city filter.

### Teams
`TeamRepository.maxTeamsPerUser = 3`, surfaced as `TeamLimitException` so the
UI can prompt the user to leave a team. Teams are **soft-disbanded**
(`disbanded_at`), and `captain_id` can be null on an already-disbanded team
whose captain deleted their account.

### Notifications
- `NotificationService` — FCM permission, foreground handling (Android needs an
  explicit local notification; iOS banners natively via presentation options),
  background handler, `getInitialMessage()` for cold-start taps.
- `FcmTokenService` — upserts this device's token on sign-in/session
  restore/refresh, removes it on sign-out so a shared device never leaks pushes.
- `notification_router.dart` — maps `type` + `reference_id` to a destination:
  match-backed types → `/matches/detail`; request-backed types → the Matches
  tab; `player_invite` → `/invitations`; `team_recruitment` → `/team`;
  otherwise the notifications list. Always calls `triggerAppRefresh()` first so
  the destination isn't stale.

---

## 9. Design system (enforced, not aspirational)

Three-tier tokens, documented in `lib/core/theme/app_tokens.dart`:

1. **Reference** — `AppSpacing` (4/8/12/16/20/24/32/48), `AppRadius` (10/12/16/20).
2. **Semantic** — `AppSemantic`, `AppElevation`, `AppOpacity`, `AppIconSize`,
   `AppFonts`, `AppTypeScale`.
3. **Component** — `app_theme.dart`, which consumes tier 2 only.

**The rule: widgets reach for tier 2, never tier 1.**

- Brand accent flips by theme — lime `#C7F032` (dark) / green `#1B7A3D`
  (light). Always `AppColors.brand(context)`, never a literal hex.
- Fonts: **Sora** (headings, display, numbers) + **Manrope** (body, labels).
- Full light/dark support via `ThemeController`; theme cross-fade is disabled
  (`themeAnimationDuration: Duration.zero`) because it looked laggy on lists.
- Motion is centralized in `AppMotion` (`core/theme/app_tokens.dart`) and reused by
  page transitions, `FadeSlideIn`, press feedback.
- Shared components in `lib/core/widgets/` (the big ones — `AmbientBackground`, `GlassCard`, `FadeSlideIn` — live in `premium.dart`) — `GlassCard`, `GradientHeader`,
  `BrandLogo`, `GradientAvatar`, `RankBadge`, `CaptainArmband`, `GradientPill`,
  `LevelBadge`, `PulseDot`, `PressableScale`, `FadeSlideIn`, `GradientText`,
  `LoadingView`/`ErrorView`/`EmptyView`, `SkeletonList`, `StatTile`,
  `StatusChip`, `AppButton`. **Reuse these; don't recreate them.**
- Auth/onboarding deliberately uses a *different* visual mode: fixed navy
  gradient + `splash_intro.mp4` video background, not the ambient theme.

`docs/UI_REDESIGN_PROMPT.md` is the canonical, self-contained brief for UI work.

### Design-token CI gate
`tool/check_design_tokens.dart` is a **ratchet**, not a hard lint: it counts raw
colors/radii/font-sizes/durations/spacers outside `lib/core/theme/` and compares
against `tool/design_token_baseline.json`. New violations fail CI; the baseline
may only go down (`--update` refuses to raise it). `--list <category>` shows
offenders.

---

## 10. Testing and CI

```
test/component_library_test.dart     shared-widget behavior
test/elo_engine_test.dart            rating math
test/match_detail_page_test.dart     score submission + proposal flows
test/match_repository_test.dart      repository query/mutation behavior
test/models_test.dart                JSON mapping
integration_test/app_launch_test.dart
integration_test/login_flow_test.dart
integration_test/support/mock_supabase.dart   mock HTTP client (no network)
```

`SupabaseService.initialize({Client? httpClient})` takes an injected HTTP client
purely so integration tests can mock the backend; production passes nothing.

Workflows in `.github/workflows/`:

- **ci.yml** (push/PR to `master`): `flutter analyze` → design-token gate →
  `flutter test` → `flutter build apk --release` (release specifically, because
  debug skips R8 + AOT and has let real breaks through). A macOS
  `flutter build ios --release --no-codesign` job runs on **pushes only**
  (10× runner cost).
- **integration.yml**: Android emulator (API 34, pixel_6) suite —
  `workflow_dispatch` and `qa/**` branches only; ~15–20 min.
- **security-scan.yml**: `dart pub outdated` + CVE scanning on push/PR and
  weekly (Mondays 06:00 UTC).

Android release enables **R8 minification**; `android/app/build.gradle.kts`
falls back to debug signing when `key.properties` is absent, so CI needs no
signing secrets.

---

## 11. Conventions to follow when changing code

1. **New backend behavior that spans rows or needs trust → write a Postgres
   RPC**, call it from a repository. Don't orchestrate multi-step mutations
   client-side.
2. **All Supabase access goes in `*/data/*_repository.dart`.** Pages call
   repositories.
3. **Models live in `lib/models/`**, immutable, `const` constructors,
   `fromJson` with defensive defaults (`?? 1500`, `?? 0`, `?? false`) and
   snake_case → camelCase mapping. Joined columns are nullable extras on the
   same model (see `MatchModel.homeTeamName`, `suggestedCourtName`).
4. **No new state-management library.** `setState` + `FutureBuilder` +
   `appRefresh`/`uiRepaint`.
5. **No raw design values** outside `lib/core/theme/` — the CI ratchet will
   catch you.
6. **Navigate via `AppRoutes` constants** and the shared `appRouter`.
7. The dense explanatory comments in `main.dart`, `app_router.dart`,
   `fcm_token_service.dart` and `match_repository.dart` record real production
   bugs. Read them before reordering or "simplifying" that code.
8. **Run before pushing:** `flutter analyze`,
   `dart run tool/check_design_tokens.dart`, `flutter test`.

---

## 12. What is *not* in this repo

- The Postgres schema, RLS policies, triggers and RPC bodies (managed in
  Supabase directly). The rating-persistence trigger and every `admin_*`
  authorization check live there.
- The `send-push` Supabase Edge Function.
- Real Supabase URL/anon key (injected via `--dart-define`) and Android signing
  keys (`key.properties`).

So: if a behavior looks unexplainable from Dart alone — a rating that moves
differently than `EloEngine` predicts, a mutation that cascades, a permission
denial — the answer is almost certainly in the database, not in this codebase.
