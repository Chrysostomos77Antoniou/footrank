import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/onboarding/onboarding_prefs.dart';
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

    context.go(AppRoutes.home);

    String? target;
    if (intent == OnboardingIntent.createTeam) {
      target = AppRoutes.createTeam;
    } else if (intent == OnboardingIntent.freeAgent) {
      target = AppRoutes.freeAgents;
    }
    if (target == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.push(target!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Your Pitch Power'),
        automaticallyImplyLeading: false,
      ),
      body: AmbientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FadeSlideIn(
                  child: Text(
                    'A quick 10-question quiz',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 40),
                  child: Text(
                    'This sets your starting skill level so your very first '
                    'matches are fairly matched. It only affects your hidden '
                    'starting rating -- real results move it from here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppSemantic.sectionGap),
                for (var i = 0; i < _dropdownQuestions.length; i++) ...[
                  FadeSlideIn(
                    delay: Duration(milliseconds: 60 + i * 40),
                    child: _DropdownQuestionCard(
                      question: _dropdownQuestions[i],
                      value: _answers[_dropdownQuestions[i].key],
                      onChanged: (v) =>
                          setState(() => _answers[_dropdownQuestions[i].key] = v!),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                for (var i = 0; i < _ratingQuestions.length; i++) ...[
                  FadeSlideIn(
                    delay: Duration(
                        milliseconds: 60 + (_dropdownQuestions.length + i) * 40),
                    child: _RatingQuestionCard(
                      question: _ratingQuestions[i],
                      value: _answers[_ratingQuestions[i].key],
                      onChanged: (v) =>
                          setState(() => _answers[_ratingQuestions[i].key] = v),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                const SizedBox(height: AppSpacing.md),
                FadeSlideIn(
                  delay: Duration(milliseconds: 60 + _totalQuestions * 40),
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('See My Pitch Power'),
                  ),
                ),
              ],
            ),
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
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question.title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            decoration: const InputDecoration(hintText: 'Choose an answer'),
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
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var n = 1; n <= 5; n++) ...[
                if (n > 1) const SizedBox(width: AppSpacing.xs),
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
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  question.lowLabel,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              Text(
                question.highLabel,
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
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
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: AnimatedContainer(
        duration: AppMotion.micro,
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
