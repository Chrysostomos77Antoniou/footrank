import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:footrank/core/widgets/app_button.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/onboarding/onboarding_prefs.dart';
import 'package:footrank/payment/data/promo_repository.dart';
import 'package:footrank/pwr_assessment/data/pwr_assessment_repository.dart';
import 'package:footrank/routing/app_router.dart';

/// One dropdown-style question: [key] and each option's key must match a row
/// in the server's `pwr_assessment_weights` table exactly, since the score is
/// computed from these keys, not from the label text.
class _Question {
  final String key;
  final String title;
  final List<(String key, String label)> options;
  const _Question(this.key, this.title, this.options);
}

/// A 1-5 self-rating question (pace, technique, etc). Answer keys are the
/// literal strings '1'..'5'.
class _RatingQuestion {
  final String key;
  final String title;
  final String lowLabel;
  final String highLabel;
  const _RatingQuestion(this.key, this.title, this.lowLabel, this.highLabel);
}

const _dropdownQuestions = [
  _Question('years_playing', 'How many years have you been playing football (organized or casual)?', [
    ('lt_1', 'Less than 1 year'),
    ('1_3', '1–3 years'),
    ('3_6', '3–6 years'),
    ('6_10', '6–10 years'),
    ('10_plus', '10+ years'),
  ]),
  _Question('highest_level', "What's the highest level you've played at?", [
    ('never_organized', 'Never played organized football'),
    ('school_casual', 'School / casual pickup games only'),
    ('amateur_league', 'Local amateur / Sunday league'),
    ('club_academy_youth', 'Club academy (youth) or a competitive regional league'),
    ('semipro_varsity', 'Semi-pro, college varsity, or senior academy level'),
    ('pro_expro', 'Professional or ex-professional'),
  ]),
  _Question('play_frequency', 'How often do you currently play?', [
    ('rarely', "Rarely — I'm just starting out"),
    ('few_times_month', 'A few times a month'),
    ('weekly', 'At least once a week'),
    ('multiple_weekly', 'Multiple times a week'),
  ]),
  _Question('formal_coaching', 'Have you ever trained at a club academy or received formal coaching?', [
    ('no', 'No'),
    ('briefly', 'Yes, briefly'),
    ('multiple_years', 'Yes, for several years'),
  ]),
  _Question('competitive_mentality', 'How would you describe your mentality in a competitive match?', [
    ('casual_fun', 'Just here to have fun'),
    ('balanced', 'A mix of fun and competitive'),
    ('very_competitive', 'Very competitive — I want to win'),
  ]),
];

const _ratingQuestions = [
  _RatingQuestion('pace', 'Rate your pace / speed', 'Slow', 'Very fast'),
  _RatingQuestion('technique', 'Rate your passing and ball control', 'Rough', 'Excellent'),
  _RatingQuestion('shooting', 'Rate your shooting / finishing', 'Rarely score', 'Clinical'),
  _RatingQuestion('stamina', 'Rate your stamina / fitness', 'Tire fast', 'Full 90 minutes'),
  _RatingQuestion('game_iq', 'Rate your decision-making / football IQ', 'Still learning', 'Reads the game well'),
];

/// One-time onboarding quiz that sets a new player's starting hidden Pitch
/// Power instead of everyone beginning at a flat 1500. Required before a
/// brand-new account can create or join a team (server-enforced -- see
/// `submit_pwr_assessment` and the team RPCs' `pwr_assessment_required`
/// checks); existing accounts were grandfathered in when this shipped.
class PwrAssessmentPage extends StatefulWidget {
  const PwrAssessmentPage({super.key});

  @override
  State<PwrAssessmentPage> createState() => _PwrAssessmentPageState();
}

class _PwrAssessmentPageState extends State<PwrAssessmentPage> {
  final _repo = PwrAssessmentRepository();
  final Map<String, String> _answers = {};
  bool _loading = false;

  int get _totalQuestions => _dropdownQuestions.length + _ratingQuestions.length;

  Future<void> _submit() async {
    if (_answers.length < _totalQuestions) {
      showError(context, 'Please answer every question before continuing.');
      return;
    }
    setState(() => _loading = true);
    try {
      await _repo.submit(_answers);
      if (mounted) _routeAfterAssessment();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// This is the last mandatory step for a new account, so the intent chosen
  /// back on the onboarding slides (create a team / register as a free
  /// agent) is honoured here now, not in profile setup -- pushing straight to
  /// "create team" before this quiz finished would just hit the server gate.
  void _routeAfterAssessment() {
    final intent = OnboardingPrefs.postSetupIntent;
    OnboardingPrefs.setPostSetupIntent(null);

    // Grab the router before navigating: this page is torn down by go(), and
    // the promo prompt and intent target below run after that.
    final router = GoRouter.of(context);
    router.go(AppRoutes.home);

    String? target;
    if (intent == OnboardingIntent.createTeam) {
      target = AppRoutes.createTeam;
    } else if (intent == OnboardingIntent.freeAgent) {
      target = AppRoutes.freeAgents;
    }
    // First sign-in: offer the promo code field before the intent target, so
    // the code is on the account before they create or join a team. Skipped
    // once the promo has ended.
    final offerPromo = PromoRepository.isOpen;
    final dest = target;
    if (dest == null && !offerPromo) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (offerPromo) {
        await router.push<void>(AppRoutes.promoCode);
      }
      if (dest != null) router.push(dest);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final muted = AppColors.muted(context);
    final accent = AppColors.brand(context);
    final answered = _answers.length;

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Find Your Pitch Power',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            letterSpacing: -0.26,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Container(
                          height: 4,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.1),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: 1,
                            child: ColoredBox(color: accent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DefaultTextStyle(
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('STEP 2 OF 2'),
                            Text('$answered OF $_totalQuestions ANSWERED'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      FadeSlideIn(
                        child: Text(
                          'A quick 10-question quiz',
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.18,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 40),
                        child: Text(
                          'This sets your starting skill level so your very first '
                          'matches are fairly matched. It only affects your hidden '
                          'starting rating -- real results move it from here.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: muted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Stack(
                          children: [
                            SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 36),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0;
                                      i < _dropdownQuestions.length;
                                      i++) ...[
                                    FadeSlideIn(
                                      delay: Duration(milliseconds: 60 + i * 40),
                                      child: _DropdownQuestionCard(
                                        question: _dropdownQuestions[i],
                                        value:
                                            _answers[_dropdownQuestions[i].key],
                                        onChanged: (v) => setState(() =>
                                            _answers[_dropdownQuestions[i]
                                                .key] = v!),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  for (var i = 0;
                                      i < _ratingQuestions.length;
                                      i++) ...[
                                    FadeSlideIn(
                                      delay: Duration(
                                          milliseconds: 60 +
                                              (_dropdownQuestions.length + i) *
                                                  40),
                                      child: _RatingQuestionCard(
                                        question: _ratingQuestions[i],
                                        value: _answers[_ratingQuestions[i].key],
                                        onChanged: (v) => setState(() =>
                                            _answers[_ratingQuestions[i].key] =
                                                v),
                                      ),
                                    ),
                                    if (i < _ratingQuestions.length - 1)
                                      const SizedBox(height: 12),
                                  ],
                                ],
                              ),
                            ),
                            // Soft fade so cards dissolve into the pinned CTA.
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 36,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [bg.withValues(alpha: 0), bg],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: AppButton(
                  label: 'See My Pitch Power',
                  loading: _loading,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropdownQuestionCard extends StatelessWidget {
  final _Question question;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _DropdownQuestionCard({
    required this.question,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.title,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, height: 1.35),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.muted(context)),
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: 'Choose an answer',
              fillColor: isDark ? AppColors.darkElevated : AppColors.lightCard,
              constraints: const BoxConstraints(minHeight: 52),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            items: question.options
                .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _RatingQuestionCard extends StatelessWidget {
  final _RatingQuestion question;
  final String? value;
  final ValueChanged<String> onChanged;

  const _RatingQuestionCard({
    required this.question,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.muted(context);
    final captionStyle = TextStyle(fontSize: 12, color: muted);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.title,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var n = 1; n <= 5; n++) ...[
                if (n > 1) const SizedBox(width: 8),
                Expanded(
                  child: _RatingChip(
                    label: '$n',
                    selected: value == '$n',
                    onTap: () => onChanged('$n'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(question.lowLabel, style: captionStyle)),
              Text(question.highLabel,
                  textAlign: TextAlign.right, style: captionStyle),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RatingChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(AppSemantic.statusPillRadius);
    final Color fill = selected
        ? AppColors.action
        : (isDark ? AppColors.darkElevated : AppColors.lightBg);
    final Color? border = selected
        ? (isDark ? null : AppColors.limeDeep)
        : (isDark ? null : AppColors.border(context));
    return Semantics(
      button: true,
      selected: selected,
      label: '$label out of 5',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: reduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: border == null
                ? null
                : Border.all(color: border, width: selected ? 1.5 : 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              color: selected
                  ? AppColors.onAction(context)
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
