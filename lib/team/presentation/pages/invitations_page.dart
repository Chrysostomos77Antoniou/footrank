import 'package:flutter/material.dart';
import 'package:footrank/core/utils/error_text.dart';
import 'package:footrank/core/widgets/async_views.dart';
import 'package:footrank/models/invitation_model.dart';
import 'package:footrank/team/data/team_repository.dart';

class InvitationsPage extends StatefulWidget {
  const InvitationsPage({super.key});

  @override
  State<InvitationsPage> createState() => _InvitationsPageState();
}

class _InvitationsPageState extends State<InvitationsPage> {
  final _repo = TeamRepository();
  late Future<List<InvitationModel>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _repo.fetchMyInvitations();
    });
  }

  Future<void> _accept(InvitationModel inv) async {
    try {
      await _repo.acceptInvitation(inv);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You joined ${inv.teamName}')),
        );
      }
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _decline(InvitationModel inv) async {
    try {
      await _repo.declineInvitation(inv);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Team Invitations')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<InvitationModel>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingView();
            }
            if (snapshot.hasError) {
              return ErrorView(onRetry: _reload);
            }
            final invites = snapshot.data ?? [];
            if (invites.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  EmptyView(
                    icon: Icons.mail_outline,
                    title: 'No pending invitations',
                    hint: 'Team captains can invite you from Free Agents.',
                  ),
                ],
              );
            }
            return ListView.builder(
              itemCount: invites.length,
              itemBuilder: (context, i) {
                final inv = invites[i];
                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(inv.teamName,
                            style:
                                Theme.of(context).textTheme.titleMedium),
                        if (inv.teamCity != null)
                          Text(inv.teamCity!,
                              style:
                                  Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _decline(inv),
                              child: const Text('Decline'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => _accept(inv),
                              child: const Text('Accept'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
