import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/widgets/brand_widgets.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/team/presentation/widgets/team_ui.dart';
import 'package:footrank/team/data/team_repository.dart';
import 'package:footrank/core/widgets/feedback.dart';
import 'package:footrank/core/app_refresh.dart';

class JoinTeamPage extends StatefulWidget {
  const JoinTeamPage({super.key});

  @override
  State<JoinTeamPage> createState() => _JoinTeamPageState();
}

class _JoinTeamPageState extends State<JoinTeamPage> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _repo = TeamRepository();
  bool _loading = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final teamName = await _repo.joinByCode(_codeCtrl.text);
      if (mounted) {
        triggerAppRefresh();
        showSuccess(context, 'You joined $teamName');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              const TeamPageHeader(title: 'Join Team'),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const FadeSlideIn(
                          child: TeamHero(
                            icon: Icons.vpn_key_outlined,
                            title: 'Join a team',
                            subtitle:
                                'Enter the invite code shared by the team captain.',
                          ),
                        ),
                        const SizedBox(height: 32),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 120),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const TeamFieldLabel('Invite Code'),
                              TextFormField(
                                controller: _codeCtrl,
                                textCapitalization:
                                    TextCapitalization.characters,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 3.2),
                                decoration: teamFieldDecoration(context,
                                    hint: 'Invite Code',
                                    icon: Icons.vpn_key_outlined),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Invite code is required'
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: BrandButton(
                  label: 'Join Team',
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
