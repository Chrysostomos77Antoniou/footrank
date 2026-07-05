import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:footrank/core/constants/cities.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/premium.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/team/data/team_repository.dart';

class CreateTeamPage extends StatefulWidget {
  const CreateTeamPage({super.key});

  @override
  State<CreateTeamPage> createState() => _CreateTeamPageState();
}

class _CreateTeamPageState extends State<CreateTeamPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _repo = TeamRepository();
  String? _city;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final team = await _repo.createTeam(
        name: _nameCtrl.text.trim(),
        city: _city,
      );
      if (mounted) {
        await _showInviteCodeDialog(team);
      }
      if (mounted) {
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showInviteCodeDialog(TeamModel team) async {
    final code = team.inviteCode;
    if (code == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Team created!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                "Share this invite code now so your squad can join before "
                "your first match."),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(code,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3)),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Invite code copied')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Team')),
      body: AmbientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                      child: Icon(Icons.shield_outlined,
                          size: 52, color: AppColors.iconAccent(context))),
                  const SizedBox(height: 8),
                  const Center(
                    child: GradientText('Start your squad',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 4),
                  Text('You\'ll be the captain. Add a logo later from the team page.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Team Name',
                      prefixIcon: Icon(Icons.shield_outlined),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Team name is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _city,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                    items: kCities
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _city = v),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create Team'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
