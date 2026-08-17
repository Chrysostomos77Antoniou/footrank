# FootRank Design System Redesign — Design Spec

**Date:** 2026-08-16
**Status:** Approved
**Target device floor:** Samsung Galaxy A70 (Android 11 / API 30, Snapdragon 675 / Adreno 612, 60Hz) — 16ms frame budget

---

## Overview

FootRank does not have a design problem. It has a design system that the app does not use.

The foundation in `lib/core/theme/` is sound: a 4px spacing scale, a 4-step radius scale, real motion tokens with intent-naming doc comments, light and dark generated from one `_base(Brightness)` function, and a considered brightness-aware accent swap. Below that foundation, enforcement collapsed. 27 of 43 UI files never import the token file. The theme file itself violates the scale it defines. The same match status renders in different colours on different screens.

This redesign is therefore an **enforcement and consolidation** project, not a repaint. It adds the missing semantic token tier, builds the component layer that was never built, unifies three competing motion systems into one, removes a continuous full-screen repaint, establishes accessibility floors, and adds the credibility signals a ranking product needs in order to be believed.

---

## Goals

1. **Trust** — the app reads as official rather than hobbyist; users believe the rating number
2. **Professional** — one concept renders one way everywhere, enforced by tooling rather than discipline
3. **Simple** — hierarchy comes from size and containment, not from new colours or typefaces
4. **Smooth** — every frame inside 16ms on the A70; motion is feedback, never decoration

## Non-goals

- Rebranding. The navy + lime identity, Sora/Manrope pairing, `PressableScale` press signature, and `GlassCard` tint model are kept and extended, not re-litigated.
- Adopting Material 3 Expressive as a framework. Flutter has paused it (see Research Basis); we adopt its *principles* on stock M3.
- Scoped leaderboards and a second effort-based ladder. Correct eventual destination, but product roadmap, not redesign.

---

## Research Basis

Primary sources fetched and verified during research:

| Area | Source |
|---|---|
| M3 Expressive paused in Flutter | [flutter/flutter#168813](https://github.com/flutter/flutter/issues/168813) — "we are not actively developing Material 3 Expressive… all future Expressive work will happen in standalone packages" |
| M3 colour token roles | [material-web.dev/theming/color](https://material-web.dev/theming/color/) |
| M3 tonal elevation, type scale | [developer.android.com — Material 3 design systems](https://developer.android.com/develop/ui/compose/designsystems/material3) |
| Motion tokens (exact values) | `packages/flutter/lib/src/material/motion.dart`, Flutter 3.32.6 — generated from Google's Material token database |
| Credibility / first impressions | Stanford Web Credibility Project (4,500+ participants; **46.1%** of credibility comments referenced design look); Lindgaard et al. 2006 (**50ms** to form an impression); Reinecke et al. 2013 (**~48%** of first-impression variance from visual complexity + colourfulness) |
| Typography, palette, hierarchy limits | Nielsen Norman Group — **1–2 fonts max**, **2–3 colours max**, primary component **30–50% larger** than its surroundings |
| Contrast / target size | WCAG 2.2 — **4.5:1** normal text (SC 1.4.3), **3:1** large text and non-text affordances (SC 1.4.11), **24×24** minimum target (SC 2.5.8); Flutter's own checklist specifies **48×48** |
| Ranking credibility patterns | Strava (segment scoping, KOM + Local Legend dual ladder), Playtomic (reliability %), UTR (verified vs open rating), chess.com (delta explanation) |

**Key constraint discovered:** M3 motion tokens (`Durations`, `Easing`) already ship in Flutter 3.32.6. `AppMotion` reinvented them slightly off-spec. We re-source rather than invent.

---

## Current State (measured, not estimated)

**Token adoption**
- `app_tokens.dart:3` declares itself "the single source of truth"; `app_theme.dart` then hardcodes `circular(20)` (chipTheme, L206), `circular(14)` (snackBar, L213), button min-height 52 (L134/148), NavigationBar height 70 (L182), and `onSurface` hex literals (L69)
- 27 / 43 UI files never import `app_tokens.dart`
- 222 / 328 `SizedBox` spacers use magic numbers
- 41 / 72 `BorderRadius.circular()` calls bypass `AppRadius` — shipping radii of 3, 4, 6, 8, 9, 10, 11, 12, 14, 16, 18, 20, 999
- 80 raw `fontSize:` overrides bypass the TextTheme, including off-scale 12.5, 13, 15.5, 26
- `AppMotion` referenced 9 times against 81 hand-typed `Duration(milliseconds: N)`
- `analysis_options.yaml` is stock `flutter_lints` with the entire rules block commented out

**Duplication**
- Two classes both named `_StatusChip` render the same match state in **different colours**: `admin_matches_page.dart:330` (string-derived, `AppRadius.sm`) vs `match_detail_page.dart:880` (enum-derived, `colorScheme.tertiary`, radius 12)
- Four stat-tile implementations: `profile_page.dart:509`, `profile_sheets.dart:323`, `team_page.dart:605`, `admin_widgets.dart:90` — padding 20/12 vs 18/12 vs 20; number size 24 vs 18 vs `displaySmall`; only one uses tabular figures
- Five chip implementations at radii 9 / 10 / 12 / 12 / 20
- Four primary buttons: `BrandButton` (radius 16, `PressableScale` + haptic, 4 uses), `AuthPrimaryButton` (near-identical copy), `_PrimaryCta` (hand-rolled in `home_page.dart`), themed `FilledButton` (radius 12, ripple, **no haptic**, 49 uses)
- Two `_CourtRow`, two `_NavItem`, two `_SectionLabel` classes with incompatible constructors
- `matches_page.dart:962` forked `GlassTabs` into `_SectionTabs` purely to add a badge

**Feedback**
- 125 raw `SnackBar(content: Text(...))` across 21 files with no success/error/undo distinction (`matches_page.dart` alone: 25)
- 14 hand-rolled `showDialog<bool>` destructive confirmations, danger-red style copy-pasted 9×
- The admin panel has `kAdminDialogAnimationStyle` (220ms/160ms) while all 14 consumer dialogs use Flutter's 150ms default — the internal tool has better modal timing than the shipped app

**Motion**
- Three competing systems: `app_router.dart:62-89` (280ms in / 220ms out, `Offset(0, 0.04)`, `Curves.easeOutCubic`), `app_theme.dart:8-43` (framework default duration, `Offset(0, 0.02)`, `AppMotion.easeOut`), `FadeSlideIn` (320ms) — so a page finishes moving before its contents do
- **iOS runs two different push animations**: auth routes and all 5 shell branches fall through to `CupertinoPageTransitionsBuilder` (horizontal), while 13 detail routes drift vertically
- Uncapped index-multiplied staggers inside `itemBuilder`s (`40 * i`, `50 * e.key`, `60 * i`) — row 39 of a leaderboard waits **1,560ms**; Material's rule is ≤20ms apart
- `FadeSlideIn` is a keyless `StatefulWidget`, so recycled list rows re-fade mid-scroll
- Zero `Hero`, one `AnimatedSwitcher`, one `AnimatedCount` call site — in a ranking app
- 14+ sites hard-cut from `LoadingView`/`SkeletonList` to content with no crossfade; the shimmer built to feel premium vanishes in a single frame
- Reduced motion checked in only 2 of ~15 animated widgets, and both use `MediaQuery.disableAnimations` which is **Android-only** — iOS Reduce Motion never sets it

**Performance**
- `premium.dart:19-22` starts a 20s `repeat(reverse: true)` controller unconditionally, behind 21 screens
- `_AmbientBlobs.paint` (L103-134) draws a full-viewport dot grid (~420 `drawCircle` at 28px spacing), then constructs three fresh `RadialGradient` shaders plus a vignette — **every frame, forever**
- The dot grid does not depend on `t` at all: static content redrawn 60×/second
- No `RepaintBoundary` around it, so the entire screen re-rasterises continuously. Only 2 `RepaintBoundary` usages exist in the whole codebase

**Accessibility**
- `Semantics|semanticLabel|MergeSemantics` across all 92 lib files: **0 results**
- `PressableScale` (`premium.dart:275`) is a bare `GestureDetector` — every tappable `GlassCard` (50 sites), `GlassTabs`, `BrandButton` is invisible to TalkBack/VoiceOver
- Tap-target floor is 44 (`app_theme.dart:101, 159`) — 4dp under Flutter's own 48 guidance
- Light mode: `onSurface` pinned to pure `0xFF000000` with muted derived at 0.82 alpha, so there is effectively no text hierarchy; the light border is defined twice with different values (`0xFFE6E8EC` vs `0xFFE3E6EB`) and is the *sole* affordance on `OutlinedButton` and `InputDecoration`, where SC 1.4.11 requires 3:1
- `pitch_power_preview.dart:66` hardcodes `AppColors.lime` on a white card ≈ **1.5:1** — effectively invisible in light mode

---

## Design Principles

1. **Tokens are a constraint, not a suggestion.** Every colour, radius, spacing, duration, font size, icon size and opacity resolves through a token, enforced by lint. `app_theme.dart` must be the first file that obeys its own scale.
2. **One concept, one component, semantic variants only.** Forking a shared widget to add a feature is banned; add the parameter instead.
3. **Motion is feedback, never decoration.** Every animation must confirm an action, communicate a state change, express spatial navigation, or signify affordance. If it does none, delete it.
4. **A screen and its contents arrive as one event.** Page transition duration, curve, and content entrance come from the same token.
5. **Trust is built at the honest moment, not by polish.** Distinguish "no matches yet" from "couldn't load matches". Distinguish confirmed from failed. Show the rating delta and its cause at the emotional peak.
6. **Restraint reads as official.** One accent reserved for the primary action. No decorative multi-hue gradients. Tabular figures on every rating, score, rank and time.
7. **Hierarchy from size and containment, not new colours.** Primary action 30–50% larger and differently shaped; group with tinted surface containers, not hairlines.
8. **Accessibility floors are design inputs, not a later audit.** 48×48 targets, 4.5:1 text, 3:1 sole-affordance borders, `Semantics` on every tappable surface, error signalled by icon + text never colour alone, reduced motion honoured on **both** platforms.
9. **Budget frames like pixels.** Animate only transform and opacity. Never animate width/height/shadow per frame. No `BackdropFilter` inside a scrolling list. `memCacheWidth/Height` on every `CachedNetworkImage`; `itemExtent` on every fixed-height `ListView.builder`. Place `RepaintBoundary` after measuring with `debugRepaintRainbowEnabled`, not defensively.
10. **Reuse the good decisions already here.** The 4px scale, the radius scale, `PressableScale`'s 0.97 + selection haptic, `GlassCard`'s tint parameter, the `EmptyView` pattern, the brightness-aware accent swap, asymmetric forward/reverse curves, `themeAnimationDuration: Duration.zero`, and `VideoSplashOverlay`'s asset-failure fallback are all correct.

---

## Architecture

### Token tiers

M3's rule is three tiers, where component tokens point at *system* tokens and never at reference tokens. FootRank has tier 1 and tier 3; widgets reach past the gap.

```
Tier 1 — Reference (exists, keep)
  AppSpacing  4 / 8 / 12 / 16 / 20 / 24 / 32 / 48
  AppRadius   sm 10 / md 12 / lg 16 / xl 20

Tier 2 — Semantic (NEW — the missing layer)
  AppSemantic.cardRadius, controlRadius, chipRadius, pill,
              screenPadding, sectionGap, rowGap, cardPadding
  AppElevation.flat / raised / overlay        (NEW)
  AppOpacity.disabled / muted / scrim / divider (NEW)
  AppIconSize.sm / md / lg                     (NEW)
  AppFonts.display / body / numeric            (NEW — numeric = tabular figures)

Tier 3 — Component
  app_theme.dart consumes ONLY tier 2. Zero literals.
```

**Surface strategy — documented decision.** The app opts out of M3 tonal elevation (`surfaceTintColor: Colors.transparent`, `elevation: 0`) and substitutes a 1px border. This is a legitimate *outlined* aesthetic and is hereby the documented strategy, expressed once as `AppElevation.flat`, so no future widget re-litigates it. Light mode gains a third surface level to match dark's three.

**Type scale — documented deviation.** FootRank's scale is intentionally compressed against M3 spec (`displayLarge` 34 vs spec 57, 1.1 line-height on headings vs ~1.12–1.25) because it is a dense sports app. This is the app's own scale and is documented as such rather than implicitly presented as M3. Body text keeps a 1.4–1.6× multiplier per NN/g.

### Enforcement

`custom_lint` rules that fail CI, banning outside `lib/core/theme/`:
- raw `Color(0x…)`
- raw `BorderRadius.circular(…)`
- raw `fontSize:`
- raw `Duration(milliseconds: …)` in widget code

`analysis_options.yaml`'s rules block is enabled at the same time.

---

## Component Library

Every duplication problem in the audit is a component that was never built. Each of these is one implementation with a variant enum — never a fork.

| Component | Replaces | Notes |
|---|---|---|
| `AppButton(variant:)` | `BrandButton`, `AuthPrimaryButton`, `_PrimaryCta`, 49 raw `FilledButton`s | primary / secondary / destructive / ghost. **All** variants get `PressableScale` + selection haptic so themed buttons stop feeling different from card taps. Label↔spinner swap wrapped in `AnimatedSwitcher` (150ms) + `AnimatedSize` |
| `StatusChip(variant:)` | 2 conflicting `_StatusChip` classes + 5 chip impls | single colour mapping derived from the `MatchStatus` enum, never from a string |
| `StatTile` | 4 stat-tile impls | tabular figures mandatory |
| `AppListRow` | 2 `_CourtRow`, 2 `_NavItem`, assorted hand-rolled rows | |
| `SectionHeader` | 2 `_SectionLabel` classes | |
| `AppNetworkImage` | raw `CachedNetworkImage` uses | enforces `memCacheWidth/Height`; 4K→384px with cache dims set is ~330KB vs ~33MB |
| `AsyncSwitcher` | 14+ hard-cut loading→content swaps | 300ms linear crossfade; skeleton sized to final content so nothing jumps |
| `confirmDestructive()` | 14 hand-rolled dialogs | enforces the destructive button is never default-focused; single copy tone |
| `showSuccess/showError/showUndo` | 125 raw SnackBars | icon + semantic colour from tokens; 4s auto-dismiss, 6s when carrying an action |
| `reduceMotion(context)` | 2 Android-only checks | `MediaQuery.disableAnimationsOf(c) \|\| platformDispatcher.accessibilityFeatures.reduceMotion` |

`GlassTabs` gains a `badges` parameter, and `matches_page.dart:962`'s `_SectionTabs` fork is deleted. A `lib/core/widgets/widgets.dart` barrel is added. The ~15 private duplicates are deleted.

---

## Motion System

`AppMotion` is rewritten against the SDK's `Durations` and `Easing` (both present in 3.32.6), keeping the existing doc-comment style.

### Durations

| Token | Value | Use |
|---|---|---|
| `pressFeedback` | 100ms (`short2`) | tap scale — inside Nielsen's 0.1s direct-manipulation window |
| `micro` | 150ms (`short3`) | icon swap, chevron rotate, checkbox, badge count |
| `small` | 200ms (`short4`) | tab indicator, chip select, expand/collapse, inline validation |
| `enter` | 300ms (`medium2`) | page push, dialog/sheet open, tab fade-through, content entrance |
| `exit` | 250ms (`medium1`) | page pop, dialog/sheet dismiss — ~17% shorter; nobody watches an exit finish |
| `hero` | 350ms in (`medium3`) / 250ms out | container transform, thumbnail → preview |
| `count` | 600ms (`long4`) | number roll-up (down from 900ms) |
| `stagger` | 30ms × first 6 rows, 0 after | total cascade capped at 180ms |
| shimmer loop | 1200ms | unchanged, already correct |
| snackbar | 250ms in / 200ms out | |

**Ceilings:** nothing the user waits on exceeds 400ms. Anything over 1,000ms shows an indicator; over 10,000ms shows determinate progress plus cancel (relevant to `app_router.dart:144-152`, which awaits `hasProfile()` behind a frozen screen for up to 6s).

### Curves

- `Easing.emphasizedDecelerate` `Cubic(0.05, 0.7, 0.1, 1.0)` — everything **entering**
- `Easing.emphasizedAccelerate` `Cubic(0.3, 0.0, 0.8, 0.15)` — everything **exiting**
- `Easing.standard` `Cubic(0.2, 0.0, 0.0, 1.0)` — begins and ends at rest on screen: press scale, tab indicator, expand/collapse, number roll-up
- `Curves.linear` — pure opacity crossfades only. `AnimatedSwitcher` defaults both curves to linear and **must always be overridden** for anything spatial.
- **Banned:** symmetric ease-in-out on entrances/exits; `Curves.linear` on anything spatial.
- Spring physics reserved for gesture-driven motion (swipe-back, sheet drag, pull-to-refresh): damping 0.8–0.9, stiffness 380–700, re-targeting from current velocity so gestures stay interruptible. Never spring colour or opacity.

### Application points

- **`app_router.dart:62-89`** — delete the bespoke 280/220 timing; source from `AppMotion`. Keep the asymmetric forward/reverse idea (the existing code comment explaining why reversing `easeOut` reads badly is correct), expressed as `emphasizedDecelerate`/`emphasizedAccelerate`.
- **`app_theme.dart:8-43, 88-96`** — `_FadeSlidePageTransitionsBuilder` becomes the single definition (its 1.0→0.88 secondary fade on the covered page is the right depth cue). **Applied to iOS too**, replacing `CupertinoPageTransitionsBuilder` at L91, so the app stops using two spatial models.
- **`app_router.dart:97-113`** (`_SwipeBackWrapper`) — replace the velocity-only >300px/s trigger with a live interactive drag driving the route animation, spring-settled on release. Keep the existing scoping to pushed pages only.
- **`premium.dart:275`** (`PressableScale`) — keep 0.97 + haptic verbatim; re-source duration, add `Semantics(button: true)`. Becomes the base of `AppButton`.
- **`premium.dart:461`** (`FadeSlideIn`) — 300ms, `emphasizedDecelerate`, offsetY reduced 24→12 (smaller travel reads as more expensive). Stagger clamped. Add an "already animated" guard keyed on item id so recycled rows stop re-fading. Drive from one controller with `Interval()` rather than 104 per-widget controllers.
- **Tab bodies** — replace bare `IndexedStack` (`rankings_page.dart:73`, `matches_page.dart:589/707/893`, `match_detail_page.dart:650`, `admin_shell.dart:66`) with `FadeThroughTransition` at 300ms linear. Fade-through, not slide: these destinations have no spatial relationship.
- **`home_shell_page.dart:66-82`** — move the async `RenderRepaintBoundary.toImage()` capture off the critical path so the first frame and the haptic fire on touch, not after the raster. Animate the nav bar itself (L199-243) with `AnimatedDefaultTextStyle` + `AnimatedScale` at 200ms — an elaborate page slide currently ends at a nav bar that hard-cuts.
- **All 14 consumer dialogs** — promote `kAdminDialogAnimationStyle` into the core theme at 300ms/250ms.
- **Shared elements** — `Hero` (or `OpenContainer`) for court thumbnail → preview and roster row → player sheet, using `MaterialRectCenterArcTween` for circular avatars and **`transitionOnUserGestures: true`** (the default `false` silently breaks the hero on Android gesture-back).
- **Reduced motion** — when set: keep duration, swap spatial motion for a plain crossfade, stop all looping animations (`ShimmerBox`, `PulseDot`), and skip the auth background video and splash intro (also gated on `accessibilityFeatures.autoPlayVideos`).

---

## Performance

**`AmbientBackground` — freeze, tokenise, drop the dot grid.**
Remove the 20s `repeat` controller entirely; paint once inside a `RepaintBoundary`. Move its 8 hardcoded hex colours into `AppColors` so the ambient layer can be retuned with the brand. Drop the dot grid — most expensive element, least visible. Nothing in the drift communicates state, so by Principle 3 it is decoration. This is the single highest-value change in the spec and it is a motion *deletion*.

Additional rules: `itemExtent` on fixed-height builders; `memCacheWidth/Height` via `AppNetworkImage`; `RepaintBoundary` placed only after measuring with `debugRepaintRainbowEnabled`.

**Verification:** `flutter run --profile` on a physical A70, reading UI-thread and raster-thread bars separately. 16ms is the pass line; 120fps is not a target on this hardware.

---

## Accessibility

| Item | Current | Target |
|---|---|---|
| `Semantics` coverage | 0 across 92 files | `Semantics(button:, label:, enabled:)` inside `PressableScale` + `GlassCard` — **one fix propagates to ~60 tap targets** |
| Tap target floor | 44 | 48×48 |
| Light-mode body text | pure `0xFF000000`, muted at 0.82 alpha | real ramp: `onSurface` ≈ `0xFF0B0F1A`, muted measured at 4.5:1 |
| Light border | defined twice, differing values, sole affordance | one constant meeting 3:1 |
| Light surfaces | 2 levels | 3, matching dark |
| `pitch_power_preview.dart:66` | `AppColors.lime` on white ≈ 1.5:1 | `AppColors.iconAccent(context)` |
| Error signalling | colour only | icon + text |

---

## Ranking Trust

Scope: **visual + credibility signals.** Scoped leaderboards and a dual skill/effort ladder are explicitly out of scope for this cycle.

**Frontend only (no backend work):**
- Tabular figures on every rating, score, rank and time
- **Neighbourhood view** — the user's row pinned with 5 above and 5 below, rest of the list scrolling. Fixes "a global table motivates only the top 5%"
- **Percentile chip** — `#412 · top 18%`, so the raw number always has a true-but-flattering companion
- Leaderboard reorder after `RefreshIndicator` animates positions (300ms `emphasizedDecelerate`) so the user can *see* who moved
- `AnimatedCount` applied to every rating, Pitch Power value, score and rank (currently 1 call site)

**Requires a confidence value from the rating system:**
- **Reliability indicator** — `Level 3.4 · 62% reliable` with a short explainer sheet; the rating's visible rate of change shrinks as confidence rises
- **"Provisional" pill** until the reliability threshold is crossed
- **Post-match delta modal** — `+14 → 1,428` shown immediately on result confirmation, with a one-line causal explanation (opponent gap, your confidence, their confidence), in a 350ms hero-scale modal

Telling a user the system already knows its estimate is uncertain, and explaining the delta at the emotional peak, is what converts a black-box number into a believable one.

---

## Phases

Each phase is independently shippable and becomes its own implementation plan.

**Phase 0 — Flutter upgrade.** 3.32.6 → latest stable, aligning local with CI. Its own isolated commit with its own A70 verification pass; **never bundled into a redesign commit**. Rationale: the local/CI mismatch is a live bug that has already shipped stale APKs once, pre-launch is the cheapest moment to take the version hit, and the Impeller Vulkan pipeline-cache work in the intervening releases specifically helps mid-range Adreno hardware. Gains predictive back and `Hero` curve customisation.

**Phase 1 — Token tier + enforcement.** Semantic tier, new token classes, `app_theme.dart` reduced to zero literals, `custom_lint` rules, `analysis_options.yaml` rules enabled.

**Phase 2 — Component library + tests.** All components above, barrel file, first widget and golden tests. This layer currently carries 50 `GlassCard`s and 104 `FadeSlideIn`s with **zero regression coverage**.

**Phase 3 — Motion + performance.** `AppMotion` rewrite, single page transition applied on both platforms, stagger cap, `FadeSlideIn` guard, `AsyncSwitcher` rollout, tab fade-through, reduced-motion helper, `AmbientBackground` freeze, A70 profiling pass.

**Phase 4 — Rebuild home / matches / rankings** on the new component language. **Layout decisions in this phase require the user's visual sign-off before implementation** — options to be presented then, not decided in this spec.

**Phase 5 — Ranking trust features.** Neighbourhood view, percentile chip, reliability indicator, Provisional pill, post-match delta modal. Backend confidence value required.

**Phase 6 — Mechanical migration.** Remaining screens against the lint gate, largest first: `matches_page.dart` (37 raw spacers), `team_page.dart` (31), `match_detail_page.dart` (25).

---

## Testing Strategy

- **Widget tests** for every new component — variants, disabled states, semantics labels present
- **Golden tests** for the component library in both light and dark, catching silent visual drift
- **Contrast assertions** in test for the token pairs that must meet 4.5:1 / 3:1, so a future palette tweak fails CI rather than shipping
- **`custom_lint` in CI** — the enforcement layer is only real if it blocks a merge
- **Manual A70 profile pass** at the end of Phase 3 and Phase 4, reading UI vs raster threads separately
- **Reduced-motion pass** on both a physical iPhone (Settings → Accessibility → Motion) and Android, since the current check only works on one

---

## Risks

| Risk | Mitigation |
|---|---|
| Flutter upgrade breaks release build silently (has happened before) | Phase 0 is isolated, verified on a physical A70 release build before anything else starts |
| Two design systems coexist during migration | Lint gate lands in Phase 1, before new screens; migration order is largest-file-first |
| Golden tests churn on every intentional change | Goldens scoped to the component library only, not full screens |
| Freezing the ambient layer changes the feel more than expected | Visual diff on device before/after; option to keep a static gradient with the dot grid removed only |
| Backend confidence value not ready | Phase 5 splits: frontend-only items ship first, credibility signals follow |

---

## Open Items

- **Phase 4 screen layouts** — deliberately unspecified. Requires visual options and user sign-off at that phase.
- **Confidence/reliability value** — needs a decision on how it is derived from match count and opponent variance in the existing rating system before Phase 5 begins.
