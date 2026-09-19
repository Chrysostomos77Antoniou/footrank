import 'package:footrank/profile/data/profile_repository.dart';
import 'package:footrank/services/supabase_service.dart';

/// Submits the "determine your Pwr" onboarding quiz.
///
/// The client only ever sends raw answer *keys* (e.g. `{"years_playing":
/// "6_10"}`) -- the point values live in `pwr_assessment_weights` and the
/// score is computed server-side in `submit_pwr_assessment`, so a tampered
/// client can't hand itself a higher starting rating.
class PwrAssessmentRepository {
  /// Submits [answers] (question key -> answer key) and returns the
  /// resulting starting Pitch Power. Throws if any question is missing an
  /// answer, or if the assessment was already completed.
  Future<int> submit(Map<String, String> answers) async {
    final result = await SupabaseService.client.rpc(
      'submit_pwr_assessment',
      params: {'p_answers': answers},
    );
    ProfileRepository.markPwrAssessmentComplete();
    return result as int;
  }
}
