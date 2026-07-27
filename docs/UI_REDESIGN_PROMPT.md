# FootRank UI Polish Prompt

Paste this whole prompt back to an agent (or reuse it yourself) when you want a full UI pass on the app. It's self-contained — it doesn't assume the agent remembers this conversation.

---

## The prompt

You are doing a UI polish pass on **FootRank**, a Flutter (Material 3) mobile app for organizing 5-a-side football matches — teams, rankings, match requests, and player profiles. This is an **existing, shipped app with a real design system already in place** — you are refining and completing that system, not starting from a blank canvas. Do not introduce a new visual language; extend the current one and fix where it's inconsistent or unfinished.

### Ground truth: the current design system (do not invent a different one)

- **Theme**: `lib/core/theme/app_colors.dart`, `app_theme.dart`, `app_tokens.dart` are the single source of truth. Read them before changing anything. Full light + dark mode support already exists via `ThemeController` — every screen must keep working in both.
- **Brand accent flips by theme, not a fixed hex**: bright lime `#C7F032` in dark mode, deep green `#1B7A3D` in light mode (lime is illegible on white). Always reference `AppColors.brand(context)` / `AppColors.iconAccent(context)`, never hardcode a color.
- **Backdrop**: every screen sits on `AmbientBackground` — a slow-drifting layered gradient with soft glow blobs, a faint dot-grid texture, and edge vignette. Keep this as the base atmosphere; don't replace it with a flat color.
- **Cards**: `GlassCard` is the standard content container — rounded (16px), a subtle diagonal gradient fill, 1px hairline border, soft shadow. Despite the name it is currently a **solid** card, not blurred glass. Real blur (`BackdropFilter`) is used in exactly one place today (the court-photo preview modal). Decide deliberately: either (a) keep the "solid elevated card" language everywhere and just make it more consistent/polished, or (b) push specific high-impact surfaces (e.g. modals, the court preview, maybe onboarding) toward true glassmorphism — don't do both halfway.
- **Type**: Sora for headings/display/numbers, Manrope for body/labels (both already bundled, weights 400–800). Keep this pairing.
- **Spacing/radius/motion tokens**: `AppSpacing` (4/8/12/16/20/24/32/48), `AppRadius` (10/12/16/20). Motion is deliberate and uniform app-wide: 110ms press scale-to-0.97 with haptics, 200ms quick transitions, 320ms `FadeSlideIn` staggered entrances, fade+slide-up page transitions, count-up numeric animations (`AnimatedCount`), shimmer skeletons (`SkeletonList`). New UI must reuse these existing widgets and durations, not invent new ones.
- **Reusable components already built** — use them, don't recreate: `GlassCard`, `GradientHeader`, `BrandLogo`, `GradientAvatar`, `RankBadge`, `CaptainArmband`, `GradientPill`, `LevelBadge`, `PulseDot`, `PressableScale`, `FadeSlideIn`, `GradientText`, `LoadingView`/`ErrorView`/`EmptyView`, `SkeletonList`.

### App structure (bottom tab shell, 5 tabs, `go_router` + `StatefulShellRoute`)

1. **Home** (`home/presentation/pages/home_page.dart`) — team card(s), notification/invite indicators, create-match quick action.
2. **Team** (`team/presentation/pages/team_page.dart` + detail/create/edit/join/invitations sub-pages) — "My Teams" list, team detail, squad management, invite codes, disbanded-team state.
3. **Ranks** (`rankings/presentation/pages/rankings_page.dart`) — Players/Teams leaderboard toggle.
4. **Matches** (`match/presentation/pages/*`) — match requests, discovery, match detail, court picker, courts directory.
5. **Profile** (`profile/presentation/pages/*`) — own profile, stats, match history, settings actions (theme toggle, legal, sign out, delete account), edit profile, first-run profile setup.

Plus **auth/onboarding** (`login_page.dart`, `register_page.dart`, `reset_password_page.dart`, `onboarding_page.dart`) which intentionally live in a *different* visual mode: a fixed navy `authGradient` + branded video background (`splash_intro.mp4`), not the theme-adaptive ambient background.

### What to actually do

Go screen by screen (the list above) and, for each one:

1. **Audit against the design system above** — flag and fix: inconsistent spacing/radius, hardcoded colors instead of `AppColors`/theme lookups, missing dark-mode contrast checks, missing empty/loading/error states (should use `EmptyView`/`LoadingView`/`ErrorView`/`SkeletonList` rather than ad-hoc spinners or bare "no data" text), touch targets under 44px, text that doesn't respect Dynamic Type / accessibility scaling, and any screen that doesn't have `FadeSlideIn` entrance treatment where the rest of the app does.
2. **Hierarchy pass**: on data-heavy screens (Rankings, Team squad list, Match detail, Notifications), make sure the single most important number/state on the screen is the visual focus — bigger, higher-contrast, first — and secondary metadata (city, timestamps, roles) is clearly de-emphasized, not competing for attention.
3. **Density pass**: mobile screens should default to comfortable spacing and one clear primary action per screen/card — audit for any screen currently cramming too much into a single `GlassCard` or list row.
4. **Empty states**: every list-based screen (matches, invitations, join requests, notifications, free agents) needs a designed empty state via `EmptyView`, not a blank scroll area.
5. **Consistency pass on badges/chips**: `CaptainArmband`, `RankBadge`, `GradientPill`, `LevelBadge` should be used consistently for their respective meanings (role, rank, status, rating) everywhere those concepts appear — audit for any screen using ad-hoc `Container`+`Text` instead of the shared component.
6. **Auth/onboarding**: keep the distinct navy/video treatment, but make sure form fields (`AuthField`), validation states, and the 4-slide onboarding carousel match the same motion/spacing language as the rest of the app (not a separate ad-hoc style).

### Hard constraints

- Flutter + Material 3, existing package set only (no new design/UI dependencies unless you ask first).
- Must not change any Supabase RPC calls, repository method signatures, or business logic — this is a UI/presentation-layer pass only.
- Must work correctly in **both** light and dark mode — check contrast in both before calling a screen done.
- Do not touch `assets/video/splash_intro.mp4` or the auth video background as part of this pass (handled separately).
- Reuse existing widgets from `lib/core/widgets/` before creating new ones. If a new shared component is genuinely needed (e.g. a missing empty-state illustration), add it to `lib/core/widgets/` following the existing naming/structure pattern, not inline in a page file.
- Run `flutter analyze` and the existing test suite after changes; both must stay clean.
- For any screen you touch, actually run it in the preview/simulator and check both themes before marking it done — don't rely on reading the widget tree alone.

### Explicitly avoid

- A second, competing visual language (no new gradients, no new accent colors, no glassmorphism introduced only in some places).
- Decorative illustrations or stock imagery — this app's personality comes from motion, type, and the brand accent, not artwork.
- Redesigning navigation structure, renaming tabs/routes, or changing information architecture — this is a visual/UX polish pass on the existing structure, not a re-architecture.
- Dense, desktop-style data tables — this is a touch-first mobile app; use cards/rows with comfortable touch targets throughout.
- Any change that requires a new native permission, a new backend field, or a new RPC.

### Definition of done

For each screen: consistent with the token system above, has proper loading/empty/error states, passes `flutter analyze`, verified visually in both light and dark mode, and uses shared components instead of one-off styling. Report back screen-by-screen what was changed and why, and flag anything you deliberately left alone because fixing it would require a business-logic or backend change out of scope for this pass.
