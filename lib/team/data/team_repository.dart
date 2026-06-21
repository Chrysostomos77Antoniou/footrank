import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:footrank/models/invitation_model.dart';
import 'package:footrank/profile/data/profile_repository.dart'
    show normalizeImageExt, imageContentType;
import 'package:footrank/models/join_request_model.dart';
import 'package:footrank/models/team_member_model.dart';
import 'package:footrank/models/team_model.dart';
import 'package:footrank/services/supabase_service.dart';

class TeamRepository {
  static const _teams = 'teams';
  static const _members = 'team_members';
  static const _requests = 'team_join_requests';
  static const _invitations = 'team_invitations';

  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  /// A non-captain member leaves their team.
  Future<void> leaveTeam(String teamId) =>
      SupabaseService.client.rpc('leave_team', params: {'p_team_id': teamId});

  /// The captain disbands (deletes) the team.
  Future<void> disbandTeam(String teamId) =>
      SupabaseService.client.rpc('disband_team', params: {'p_team_id': teamId});

  Future<List<TeamModel>> fetchAll() async {
    final data = await SupabaseService.client
        .from(_teams)
        .select()
        .order('rating', ascending: false);
    return (data as List)
        .map((e) => TeamModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TeamModel> fetchById(String id) async {
    final data =
        await SupabaseService.client.from(_teams).select().eq('id', id).single();
    return TeamModel.fromJson(data);
  }

  /// The team the current user belongs to (via team_members), or null.
  Future<TeamModel?> fetchMyTeam() async {
    final uid = _uid;
    if (uid == null) return null;

    final membership = await SupabaseService.client
        .from(_members)
        .select('teams(*)')
        .eq('user_id', uid)
        .maybeSingle();

    if (membership == null || membership['teams'] == null) return null;
    return TeamModel.fromJson(membership['teams'] as Map<String, dynamic>);
  }

  /// The name of the team a user belongs to, or null if they're a free agent.
  Future<String?> fetchUserTeamName(String userId) async {
    final data = await SupabaseService.client
        .from(_members)
        .select('teams(name)')
        .eq('user_id', userId)
        .maybeSingle();
    if (data == null) return null;
    return (data['teams'] as Map<String, dynamic>?)?['name'] as String?;
  }

  /// Members of a team with their user info, captain first.
  Future<List<TeamMemberModel>> fetchMembers(String teamId) async {
    final data = await SupabaseService.client
        .from(_members)
        .select(
            '*, users(name, username, position, elo, reliability, behavior_positive, behavior_negative)')
        .eq('team_id', teamId);

    final members = (data as List)
        .map((e) => TeamMemberModel.fromJson(e as Map<String, dynamic>))
        .toList();

    // captain -> vice_captain -> player
    int rank(String role) =>
        role == 'captain' ? 0 : (role == 'vice_captain' ? 1 : 2);
    members.sort((a, b) => rank(a.role).compareTo(rank(b.role)));
    return members;
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Creates a team, sets the current user as captain member, returns the team.
  Future<TeamModel> createTeam({
    required String name,
    String? city,
    String? logoUrl,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('No authenticated user');

    // Guard: a user can only belong to one team. Check before inserting the
    // team row so we never create an orphan team if membership would fail.
    final existing = await fetchMyTeam();
    if (existing != null) {
      throw Exception('You are already on a team');
    }

    final inserted = await SupabaseService.client
        .from(_teams)
        .insert({
          'name': name,
          'city': city,
          'logo_url': logoUrl,
          'captain_id': uid,
          'invite_code': _generateInviteCode(),
        })
        .select()
        .single();

    final team = TeamModel.fromJson(inserted);

    await SupabaseService.client.from(_members).insert({
      'team_id': team.id,
      'user_id': uid,
      'role': 'captain',
    });

    return team;
  }

  /// Captain updates team details (name, city, logo).
  Future<TeamModel> updateTeam({
    required String teamId,
    required String name,
    String? city,
    String? logoUrl,
  }) async {
    final updated = await SupabaseService.client
        .from(_teams)
        .update({
          'name': name,
          'city': city,
          if (logoUrl != null) 'logo_url': logoUrl,
        })
        .eq('id', teamId)
        .select()
        .single();
    return TeamModel.fromJson(updated);
  }

  /// Uploads a team logo (reuses the avatars bucket, under the captain's
  /// own folder) and returns the public URL.
  Future<String> uploadLogo(List<int> bytes, String fileExt) async {
    final uid = _uid;
    if (uid == null) throw StateError('No authenticated user');
    final ext = normalizeImageExt(fileExt);
    final path = '$uid/team_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await SupabaseService.client.storage.from('avatars').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions:
              FileOptions(contentType: imageContentType(ext), upsert: false),
        );
    return SupabaseService.client.storage.from('avatars').getPublicUrl(path);
  }

  // ---- Join flow ----

  /// Sends a join request for the team matching [inviteCode].
  /// Returns the team name on success.
  Future<String> requestJoinByCode(String inviteCode) async {
    final uid = _uid;
    if (uid == null) throw StateError('No authenticated user');

    final team = await SupabaseService.client
        .from(_teams)
        .select('id, name')
        .eq('invite_code', inviteCode.trim().toUpperCase())
        .maybeSingle();

    if (team == null) {
      throw Exception('No team found with that invite code');
    }

    await SupabaseService.client.from(_requests).insert({
      'team_id': team['id'],
      'user_id': uid,
      'status': 'pending',
    });

    return team['name'] as String;
  }

  /// Pending join requests for a team (captain view).
  Future<List<JoinRequestModel>> fetchPendingRequests(String teamId) async {
    final data = await SupabaseService.client
        .from(_requests)
        .select('*, users(name, username, position, elo)')
        .eq('team_id', teamId)
        .eq('status', 'pending')
        .order('created_at');

    return (data as List)
        .map((e) => JoinRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Captain approves a request: adds the user as player and marks approved.
  Future<void> approveRequest(JoinRequestModel request) async {
    await SupabaseService.client.from(_members).insert({
      'team_id': request.teamId,
      'user_id': request.userId,
      'role': 'player',
    });

    await SupabaseService.client
        .from(_requests)
        .update({'status': 'approved'}).eq('id', request.id);
  }

  Future<void> rejectRequest(JoinRequestModel request) async {
    await SupabaseService.client
        .from(_requests)
        .update({'status': 'rejected'}).eq('id', request.id);
  }

  // ---- Role management (captain only; enforced by RLS + UI) ----

  /// Changes a member's role. The captain role cannot be reassigned here.
  Future<void> updateMemberRole({
    required String teamId,
    required String userId,
    required String role,
  }) async {
    assert(role == 'vice_captain' || role == 'player');
    await SupabaseService.client
        .from(_members)
        .update({'role': role})
        .eq('team_id', teamId)
        .eq('user_id', userId);
  }

  /// Removes a member from the team.
  Future<void> removeMember({
    required String teamId,
    required String userId,
  }) async {
    await SupabaseService.client
        .from(_members)
        .delete()
        .eq('team_id', teamId)
        .eq('user_id', userId);
  }

  // ---- Invitations (captain invites a free agent) ----

  /// Captain sends an invitation to a free agent.
  Future<void> invitePlayer({
    required String teamId,
    required String userId,
  }) async {
    await SupabaseService.client.from(_invitations).insert({
      'team_id': teamId,
      'user_id': userId,
      'status': 'pending',
    });
  }

  /// User IDs the given team currently has pending invitations for.
  Future<Set<String>> fetchPendingInviteeIds(String teamId) async {
    final data = await SupabaseService.client
        .from(_invitations)
        .select('user_id')
        .eq('team_id', teamId)
        .eq('status', 'pending');
    return (data as List).map((e) => e['user_id'] as String).toSet();
  }

  /// Pending invitations addressed to the current user.
  Future<List<InvitationModel>> fetchMyInvitations() async {
    final uid = _uid;
    if (uid == null) return [];

    final data = await SupabaseService.client
        .from(_invitations)
        .select('*, teams(name, city)')
        .eq('user_id', uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => InvitationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Invitee accepts: joins the team (while invite still pending), then
  /// marks the invitation accepted.
  Future<void> acceptInvitation(InvitationModel invitation) async {
    final uid = _uid;
    if (uid == null) throw StateError('No authenticated user');

    // Guard: one team per user.
    final existing = await fetchMyTeam();
    if (existing != null) {
      throw Exception('You are already on a team. Leave it first to join another.');
    }

    await SupabaseService.client.from(_members).insert({
      'team_id': invitation.teamId,
      'user_id': uid,
      'role': 'player',
    });

    await SupabaseService.client
        .from(_invitations)
        .update({'status': 'accepted'}).eq('id', invitation.id);
  }

  Future<void> declineInvitation(InvitationModel invitation) async {
    await SupabaseService.client
        .from(_invitations)
        .update({'status': 'declined'}).eq('id', invitation.id);
  }
}
