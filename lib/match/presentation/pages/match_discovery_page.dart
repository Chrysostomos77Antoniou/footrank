import 'package:flutter/material.dart';
import 'package:footrank/match/data/match_repository.dart';
import 'package:footrank/models/match_request_model.dart';

class MatchDiscoveryPage extends StatefulWidget {
  final String teamId;
  const MatchDiscoveryPage({super.key, required this.teamId});

  @override
  State<MatchDiscoveryPage> createState() => _MatchDiscoveryPageState();
}

class _MatchDiscoveryPageState extends State<MatchDiscoveryPage> {
  final _repo = MatchRepository();

  late Future<List<MatchRequestModel>> _myRequestsFuture;
  MatchRequestModel? _reference;
  Future<List<MatchRequestModel>>? _opponentsFuture;

  @override
  void initState() {
    super.initState();
    _myRequestsFuture = _repo.fetchSearchingRequests(widget.teamId);
  }

  final Set<String> _dismissed = {}; // locally rejected opponent request ids

  void _selectReference(MatchRequestModel ref) {
    setState(() {
      _reference = ref;
      _opponentsFuture = _repo.findOpponents(
        myTeamId: widget.teamId,
        myTeamRating: ref.teamRating ?? 1500,
        city: ref.city,
        scheduledAt: ref.scheduledAt,
      );
    });
  }

  Future<void> _accept(MatchRequestModel opponent) async {
    try {
      await _repo.acceptMatchRequest(
        requestId: opponent.id,
        awayTeamId: widget.teamId,
      );
      if (!mounted) return;
      setState(() => _dismissed.add(opponent.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Match requested against ${opponent.teamName}. '
                'Waiting for their captain to confirm.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  void _reject(MatchRequestModel opponent) {
    setState(() => _dismissed.add(opponent.id));
  }

  String _label(MatchRequestModel r) {
    final d = r.scheduledAt.toLocal();
    final date =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${r.city} · $date $time · ${r.matchType}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find Opponents')),
      body: FutureBuilder<List<MatchRequestModel>>(
        future: _myRequestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final myRequests = snapshot.data ?? [];
          if (myRequests.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Create an open match request first, then come back to find opponents.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Default to first reference once loaded.
          _reference ??= myRequests.first;
          _opponentsFuture ??= _repo.findOpponents(
            myTeamId: widget.teamId,
            myTeamRating: _reference!.teamRating ?? 1500,
            city: _reference!.city,
            scheduledAt: _reference!.scheduledAt,
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<MatchRequestModel>(
                  initialValue: _reference,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Your match request',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: myRequests
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(_label(r),
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (r) {
                    if (r != null) _selectReference(r);
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _buildOpponents()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOpponents() {
    return FutureBuilder<List<MatchRequestModel>>(
      future: _opponentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final opponents = (snapshot.data ?? [])
            .where((o) => !_dismissed.contains(o.id))
            .toList();
        if (opponents.isEmpty) {
          final ref = _reference;
          final rd = ref?.scheduledAt.toLocal();
          final refLine = rd == null
              ? ''
              : '\n\nLooking for: ${ref!.city} on '
                  '${rd.day.toString().padLeft(2, '0')}/'
                  '${rd.month.toString().padLeft(2, '0')}/'
                  '${rd.year} around '
                  '${rd.hour.toString().padLeft(2, '0')}:'
                  '${rd.minute.toString().padLeft(2, '0')}.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No matching opponents found.\n'
                'Opponents must be in the same city, on the same date '
                '(±60 min), and a similar rating.$refLine',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: opponents.length,
          itemBuilder: (context, i) {
            final o = opponents[i];
            final d = o.scheduledAt.toLocal();
            final time =
                '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
            return Card(
              margin:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text((o.teamName ?? '?')[0].toUpperCase()),
                      ),
                      title: Text(o.teamName ?? 'Unknown team'),
                      subtitle: Text('${o.city} · $time · ${o.matchType}'),
                      trailing: Text(
                        'Rating ${o.teamRating ?? '-'}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _reject(o),
                          child: const Text('Reject'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => _accept(o),
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
    );
  }
}
