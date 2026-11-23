// The community's one door to the server: sign-in, the person's profile and
// privacy, their teams and the teams they could join, the boards' numbers,
// team chat, and Humans (people they follow).
//
// LOCAL FIRST STILL HOLDS. Nothing here touches the network until the person
// opens the community and signs in: the client is not even started at launch
// for someone who never has ([resumeIfUsed]). Signed in, what leaves the phone
// is a profile and the numbers some reader is allowed to see: a board of a
// team they joined, or their followers under their privacy settings
// ([uploadScores] works out which). The server decides who reads what.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/day_label.dart';
import '../data/db.dart';
import '../data/local_repository.dart';
import '../state/prefs.dart';
import '../ui2/screens/dial_parts.dart' show dialSeries;
import '../ui2/screens/locus_age.dart' show finishedSaturdays;
import '../ui2/screens/trend_view.dart' show TrendLoader;
import 'leaderboard.dart';

/// The project the app talks to. The publishable key is meant to ship in the
/// app: row level security on the server decides what each person can read.
const String kCommunityUrl = 'https://oyxjhxrlgrexbsvyohzv.supabase.co';
const String kCommunityKey = 'sb_publishable_m5WqPpPZTDNVszvJO_XTYw_lsSWYIIZ';

/// Where Google sends the person back to after they sign in.
const String kCommunityRedirect = 'wtf.openstrap.locus://login-callback';

/// Who sees a profile field: everyone signed in, followers, or nobody.
enum Audience {
  all('All Members'),
  followers('Followers'),
  none('No One');

  const Audience(this.label);
  final String label;

  static Audience parse(Object? v) =>
      values.where((a) => a.name == v).firstOrNull ?? Audience.all;
}

/// One metric's setting for followers.
class MetricPrivacy {
  final bool followers, daily, trends;
  const MetricPrivacy(
      {this.followers = true, this.daily = true, this.trends = true});

  factory MetricPrivacy.fromJson(Object? j) {
    if (j is! Map) return const MetricPrivacy();
    return MetricPrivacy(
      followers: j['who'] != 'none',
      daily: j['daily'] != false,
      trends: j['trends'] != false,
    );
  }

  Map<String, Object> toJson() =>
      {'who': followers ? 'followers' : 'none', 'daily': daily, 'trends': trends};

  MetricPrivacy copyWith({bool? followers, bool? daily, bool? trends}) =>
      MetricPrivacy(
        followers: followers ?? this.followers,
        daily: daily ?? this.daily,
        trends: trends ?? this.trends,
      );
}

/// What followers may see, by metric. The keys match the server's.
const kPrivacyMetrics = [
  'sleep',
  'recovery',
  'strain',
  'activities',
  'age',
];

class CommunityProfile {
  final String id, name;
  final String? username, avatarPath, region;
  final int hue;
  final int? birthYear;
  final DateTime? createdAt;
  final Audience searchable, showAge, showRegion, showLists, showPhoto;
  final bool mutualFollow;
  final Map<String, MetricPrivacy> privacy;

  const CommunityProfile(
    this.id,
    this.name, {
    this.hue = 0,
    this.username,
    this.avatarPath,
    this.region,
    this.birthYear,
    this.createdAt,
    this.searchable = Audience.all,
    this.showAge = Audience.all,
    this.showRegion = Audience.all,
    this.showLists = Audience.all,
    this.showPhoto = Audience.all,
    this.mutualFollow = true,
    this.privacy = const {},
  });

  factory CommunityProfile.fromJson(Map<String, dynamic> j) {
    final pv = j['privacy'];
    return CommunityProfile(
      j['id'] as String,
      (j['display_name'] as String?) ?? 'Member',
      hue: (j['hue'] as num?)?.toInt() ?? 0,
      username: j['username'] as String?,
      avatarPath: j['avatar_path'] as String?,
      region: j['region'] as String?,
      birthYear: (j['birth_year'] as num?)?.toInt(),
      createdAt: DateTime.tryParse('${j['created_at']}'),
      searchable: Audience.parse(j['searchable']),
      showAge: Audience.parse(j['show_age']),
      showRegion: Audience.parse(j['show_region']),
      showLists: Audience.parse(j['show_lists']),
      showPhoto: Audience.parse(j['show_photo']),
      mutualFollow: j['mutual_follow'] != false,
      privacy: {
        for (final k in kPrivacyMetrics)
          k: MetricPrivacy.fromJson(pv is Map ? pv[k] : null),
      },
    );
  }

  MetricPrivacy privacyOf(String metric) =>
      privacy[metric] ?? const MetricPrivacy();
}

/// A team's boards: what joining it shares with it.
class Boards {
  final bool strain, recovery, sleep;
  const Boards({this.strain = true, this.recovery = true, this.sleep = true});

  factory Boards.fromJson(Map<String, dynamic> j) => Boards(
        strain: j['board_strain'] != false,
        recovery: j['board_recovery'] != false,
        sleep: j['board_sleep'] != false,
      );

  /// "Strain, and Recovery", as the info page words it.
  String get words {
    final on = [if (strain) 'Strain', if (recovery) 'Recovery', if (sleep) 'Sleep'];
    if (on.length < 2) return on.join();
    return '${on.sublist(0, on.length - 1).join(', ')}, and ${on.last}';
  }

  bool has(BoardMetric m) => switch (m) {
        BoardMetric.strain => strain,
        BoardMetric.recovery => recovery,
        BoardMetric.sleep => sleep,
      };

  /// The boards it has, in the tab order.
  List<BoardMetric> get list => [
        if (strain) BoardMetric.strain,
        if (recovery) BoardMetric.recovery,
        if (sleep) BoardMetric.sleep,
      ];
}

class CommunityTeam {
  final String id, name, code, role, description, banner, logo;
  final bool isOpen, isPublic, chatEnabled;
  final Boards boards;
  final DateTime lastReadAt;
  final int unread;

  /// Null until counted.
  final int? members;

  const CommunityTeam(
    this.id,
    this.name,
    this.code, {
    this.isOpen = false,
    this.isPublic = false,
    this.chatEnabled = false,
    this.role = 'member',
    this.description = '',
    this.banner = 'banner_1',
    this.logo = 'heart',
    this.boards = const Boards(),
    required this.lastReadAt,
    this.unread = 0,
    this.members,
  });

  bool get isAdmin => role == 'owner' || role == 'admin';
  bool get isOwner => role == 'owner';

  /// The open community never has chat, whatever its row says.
  bool get hasChat => chatEnabled && !isOpen;

  CommunityTeam copyWith({int? unread, int? members}) => CommunityTeam(
        id,
        name,
        code,
        isOpen: isOpen,
        isPublic: isPublic,
        chatEnabled: chatEnabled,
        role: role,
        description: description,
        banner: banner,
        logo: logo,
        boards: boards,
        lastReadAt: lastReadAt,
        unread: unread ?? this.unread,
        members: members ?? this.members,
      );
}

/// A team as someone who has not joined it sees it: enough to decide.
class TeamPreview {
  final String id, name, description, banner, logo;
  final bool isPublic, chatEnabled, joined;
  final Boards boards;
  final int members;
  const TeamPreview(
    this.id,
    this.name, {
    this.description = '',
    this.banner = 'banner_1',
    this.logo = 'heart',
    this.isPublic = false,
    this.chatEnabled = false,
    this.joined = false,
    this.boards = const Boards(),
    this.members = 0,
  });

  factory TeamPreview.fromJson(Map<String, dynamic> j) => TeamPreview(
        j['id'] as String,
        j['name'] as String,
        description: (j['description'] as String?) ?? '',
        banner: (j['banner'] as String?) ?? 'banner_1',
        logo: (j['logo'] as String?) ?? 'heart',
        isPublic: j['is_public'] == true,
        chatEnabled: j['chat_enabled'] == true,
        joined: j['joined'] == true,
        boards: Boards.fromJson(j),
        members: (j['members'] as num?)?.toInt() ?? 0,
      );
}

/// A team's member.
class TeamPerson {
  final String id, name, role;
  final String? username, avatarPath;
  final int hue;
  const TeamPerson(this.id, this.name,
      {this.role = 'member', this.username, this.avatarPath, this.hue = 0});

  factory TeamPerson.fromJson(Map<String, dynamic> j) => TeamPerson(
        j['id'] as String,
        (j['display_name'] as String?) ?? 'Member',
        role: (j['role'] as String?) ?? 'member',
        username: j['username'] as String?,
        avatarPath: j['avatar_path'] as String?,
        hue: (j['hue'] as num?)?.toInt() ?? 0,
      );

  bool get isAdmin => role == 'owner' || role == 'admin';
}

/// Someone found by search, or opened from a list.
class Human {
  final String id, name;
  final String? username, avatarPath, region;
  final int hue;
  final int? birthYear, followers, following;
  final DateTime? memberSince;

  /// My follow of them: null, 'pending' or 'accepted'.
  final String? followState;
  final bool followsMe, listsVisible;

  const Human(
    this.id,
    this.name, {
    this.username,
    this.avatarPath,
    this.region,
    this.hue = 0,
    this.birthYear,
    this.followers,
    this.following,
    this.memberSince,
    this.followState,
    this.followsMe = false,
    this.listsVisible = false,
  });

  factory Human.fromJson(Map<String, dynamic> j) => Human(
        j['id'] as String,
        (j['display_name'] as String?) ?? 'Member',
        username: j['username'] as String?,
        avatarPath: j['avatar_path'] as String?,
        region: j['region'] as String?,
        hue: (j['hue'] as num?)?.toInt() ?? 0,
        birthYear: (j['birth_year'] as num?)?.toInt(),
        followers: (j['followers'] as num?)?.toInt(),
        following: (j['following'] as num?)?.toInt(),
        memberSince: DateTime.tryParse('${j['member_since']}'),
        followState: (j['follow_state'] ?? j['status']) as String?,
        followsMe: j['follows_me'] == true,
        listsVisible: j['lists_visible'] == true,
      );

  bool get following_ => followState == 'accepted';
  bool get requested => followState == 'pending';

  /// "@handle · 35 · Budapest", the parts they show.
  String handleLine(DateTime now) => [
        if (username != null && username!.isNotEmpty) '@$username',
        if (birthYear != null) '${now.year - birthYear!}',
        if (region != null && region!.isNotEmpty) region!,
      ].join(' · ');
}

/// One workout as a board or profile shows it.
class SharedActivity {
  final String userId, kind;
  final DateTime day, startedAt;
  final double? strain, calories;
  const SharedActivity(this.userId, this.day, this.startedAt, this.kind,
      {this.strain, this.calories});

  factory SharedActivity.fromJson(Map<String, dynamic> j, {String? userId}) =>
      SharedActivity(
        userId ?? (j['user_id'] as String),
        DateTime.parse(j['day'] as String),
        DateTime.parse(j['started_at'] as String).toLocal(),
        j['kind'] as String,
        strain: (j['strain'] as num?)?.toDouble(),
        calories: (j['calories'] as num?)?.toDouble(),
      );
}

/// An admin's invitation into a team, waiting for the person's answer.
class TeamInvite {
  final TeamPreview team;
  final String? inviter;
  final DateTime? at;
  const TeamInvite(this.team, {this.inviter, this.at});

  factory TeamInvite.fromJson(Map<String, dynamic> j) => TeamInvite(
        TeamPreview.fromJson(j),
        inviter: j['inviter_name'] as String?,
        at: DateTime.tryParse('${j['invited_at']}')?.toLocal(),
      );
}

class ChatMessage {
  final int id;
  final String teamId, userId, body;
  final String? imagePath, card;
  final DateTime at;
  const ChatMessage(this.id, this.teamId, this.userId, this.body, this.at,
      {this.imagePath, this.card});

  /// Written by the server (the weekly recap), not by a member.
  bool get fromBot => userId.isEmpty;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        (j['id'] as num).toInt(),
        j['team_id'] as String,
        (j['user_id'] as String?) ?? '',
        (j['body'] as String?) ?? '',
        DateTime.parse(j['created_at'] as String).toLocal(),
        imagePath: j['image_path'] as String?,
        card: j['card'] as String?,
      );
}

/// What a new team is made with.
class NewTeam {
  final String name, description, banner, logo;
  final bool isPublic, chat;
  final Boards boards;
  final Uint8List? bannerImage, logoImage;
  const NewTeam({
    required this.name,
    this.description = '',
    this.banner = 'banner_1',
    this.logo = 'heart',
    this.isPublic = false,
    this.chat = true,
    this.boards = const Boards(),
    this.bannerImage,
    this.logoImage,
  });
}

/// The server's words for a failure, without the client's wrapping.
String communityError(Object e) {
  if (e is AuthException) return e.message;
  if (e is PostgrestException) return e.message;
  if (e is StorageException) return e.message;
  final s = '$e';
  return s.replaceFirst('Exception: ', '');
}

class CommunityService extends ChangeNotifier {
  CommunityService._();

  /// For a test's stand-in, which overrides the server calls.
  @visibleForTesting
  CommunityService.forTest();

  static CommunityService _instance = CommunityService._();
  static CommunityService get instance => _instance;
  @visibleForTesting
  static set debugInstance(CommunityService s) => _instance = s;

  /// Set once the person has signed in on this phone: from then on the
  /// client starts at launch, so the badge and the scores keep up.
  static const String kUsed = 'community.used';

  /// Set once the intro has been gone through.
  static const String kIntroSeen = 'community.intro_seen';

  /// The board the Community tab ranks my teams by.
  static const String kRankMetric = 'community.rank_metric';
  static const String kRankRange = 'community.rank_range';

  bool _ready = false;
  Future<void>? _starting;
  StreamSubscription<AuthState>? _authSub;
  RealtimeChannel? _channel;

  /// Where [uploadScores] reads the person's numbers. Set by the first screen
  /// that has one.
  LocalRepository? repo;

  SupabaseClient get _db => Supabase.instance.client;

  bool get ready => _ready;
  User? get user => _ready ? _db.auth.currentUser : null;
  bool get signedIn => user != null;
  String? get myId => user?.id;

  CommunityProfile? profile;
  List<CommunityTeam> teams = const [];
  Set<String> blocked = const {};

  /// People asking to follow me.
  List<Human> requests = const [];

  /// Teams whose admin invited me.
  List<TeamInvite> invites = const [];

  /// The team whose chat is on screen: its new messages are not unread.
  String? viewingChat;

  int get unread =>
      teams.fold(0, (n, t) => n + t.unread) + requests.length + invites.length;

  final _messages = StreamController<ChatMessage>.broadcast();

  /// Every new chat message in the person's teams, as it arrives.
  Stream<ChatMessage> get newMessages => _messages.stream;

  /// Starts the client. Cheap after the first call.
  Future<void> ensureReady() => _starting ??= _start();

  Future<void> _start() async {
    try {
      await Supabase.initialize(
          url: kCommunityUrl, publishableKey: kCommunityKey);
    } catch (e) {
      // Already initialised (a hot restart): carry on with it.
      debugPrint('community init: $e');
    }
    _ready = true;
    _authSub = _db.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn) {
        Prefs.setBool(kUsed, true);
        unawaited(refresh());
      } else if (s.event == AuthChangeEvent.signedOut) {
        _clear();
      }
    });
    if (signedIn) unawaited(refresh());
    notifyListeners();
  }

  /// At launch: wakes the client only for someone who has signed in before.
  Future<void> resumeIfUsed() async {
    if (Prefs.getBool(kUsed, false)) await ensureReady();
  }

  void _clear() {
    profile = null;
    teams = const [];
    blocked = const {};
    requests = const [];
    invites = const [];
    _channel?.unsubscribe();
    _channel = null;
    notifyListeners();
  }

  // ── sign in ──────────────────────────────────────────────────────────────

  /// In with no email and no password: an anonymous account tied to this
  /// phone. [name] and [username], from setup, become what others see.
  Future<void> join({String? name, String? username, int? birthYear}) async {
    await ensureReady();
    if (!signedIn) {
      await _db.auth.signInAnonymously();
      Prefs.setBool(kUsed, true);
    }
    await refresh();
    final p = profile;
    if (p == null) return;
    final defaultName = RegExp(r'^Member [0-9A-F]{4}$').hasMatch(p.name);
    await updateProfile({
      if (defaultName && name != null && name.trim().isNotEmpty)
        'display_name': name.trim(),
      if (p.username == null && username != null && username.trim().isNotEmpty)
        'username': username.trim().replaceFirst('@', ''),
      if (p.birthYear == null && birthYear != null) 'birth_year': birthYear,
    });
  }

  /// An anonymous account cannot be signed back into once signed out.
  bool get anonymous => user?.isAnonymous ?? false;

  /// Which ways in are switched on in the project. Each button only shows
  /// when its way is, so neither leads to "anonymous sign-ins are disabled"
  /// or "provider is not enabled". Null when the project cannot be reached.
  Future<({bool anonymous, bool google})?> signInMethods() async {
    try {
      final r = await http.get(Uri.parse('$kCommunityUrl/auth/v1/settings'),
          headers: {'apikey': kCommunityKey}).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body);
      final ext = j is Map ? j['external'] : null;
      if (ext is! Map) return null;
      return (
        anonymous: ext['anonymous_users'] == true,
        google: ext['google'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> signInWithGoogle() async {
    await ensureReady();
    await _db.auth.signInWithOAuth(OAuthProvider.google,
        redirectTo: kCommunityRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication);
  }

  Future<void> signOut() async {
    if (!_ready) return;
    await _db.auth.signOut();
    Prefs.setBool(kUsed, false);
    _clear();
  }

  /// Deletes the account and everything it put on the server.
  Future<void> deleteAccount() async {
    await _db.rpc('delete_me');
    await signOut();
  }

  // ── the person, their teams ──────────────────────────────────────────────

  Future<void> refresh() async {
    final me = myId;
    if (me == null) return;
    try {
      final p = await _db.rpc('my_profile');
      final rows = p is List ? p : const [];
      profile = rows.isEmpty
          ? null
          : CommunityProfile.fromJson(rows.first as Map<String, dynamic>);
      final mine = await _db
          .from('team_members')
          .select('role, last_read_at, teams(*)')
          .eq('user_id', me);
      final list = <CommunityTeam>[];
      for (final r in mine) {
        final t = r['teams'];
        if (t is! Map<String, dynamic>) continue;
        list.add(_teamOf(t, r['role'] as String?, r['last_read_at'] as String?));
      }
      // Your own teams first, by name; the open community last.
      list.sort((a, b) => a.isOpen != b.isOpen
          ? (a.isOpen ? 1 : -1)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final b = await _db.from('blocks').select('blocked').eq('blocker', me);
      blocked = {for (final r in b) r['blocked'] as String};
      teams = await _withCounts(list);
      requests = await followRequests();
      invites = await myInvites();
      _listen();
      notifyListeners();
      unawaited(uploadScores());
    } catch (e) {
      debugPrint('community refresh: $e');
    }
  }

  CommunityTeam _teamOf(Map<String, dynamic> t, String? role, String? lastRead) =>
      CommunityTeam(
        t['id'] as String,
        t['name'] as String,
        (t['code'] as String?) ?? '',
        isOpen: t['is_open'] == true,
        isPublic: t['is_public'] == true,
        chatEnabled: t['chat_enabled'] == true,
        description: (t['description'] as String?) ?? '',
        banner: (t['banner'] as String?) ?? 'banner_1',
        logo: (t['logo'] as String?) ?? 'heart',
        boards: Boards.fromJson(t),
        role: role ?? 'member',
        lastReadAt: DateTime.tryParse(lastRead ?? '') ?? DateTime.now(),
      );

  /// Each team's member count, and its count of messages newer than its last
  /// read (not the person's own, nor anyone they blocked).
  Future<List<CommunityTeam>> _withCounts(List<CommunityTeam> list) async {
    final me = myId;
    final out = <CommunityTeam>[];
    for (final t in list) {
      int? members;
      try {
        final pv = await _db.rpc('team_preview', params: {'team': t.id});
        if (pv is List && pv.isNotEmpty) {
          members = ((pv.first as Map)['members'] as num?)?.toInt();
        }
      } catch (_) {}
      var n = 0;
      if (t.hasChat && me != null) {
        final rows = await _db
            .from('messages')
            .select('user_id')
            .eq('team_id', t.id)
            .gt('created_at', t.lastReadAt.toUtc().toIso8601String())
            .or('user_id.is.null,user_id.neq.$me')
            .limit(100);
        n = rows.where((r) => !blocked.contains(r['user_id'])).length;
      }
      out.add(t.copyWith(unread: n, members: members));
    }
    return out;
  }

  /// Live: new chat messages in the person's teams, and follow requests.
  void _listen() {
    if (_channel != null) return;
    _channel = _db
        .channel('community-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final m = ChatMessage.fromJson(payload.newRecord);
            if (blocked.contains(m.userId)) return;
            _messages.add(m);
            if (m.userId == myId || m.teamId == viewingChat) return;
            teams = [
              for (final t in teams)
                t.id == m.teamId ? t.copyWith(unread: t.unread + 1) : t,
            ];
            notifyListeners();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'follows',
          callback: (_) async {
            requests = await followRequests();
            notifyListeners();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'team_invites',
          callback: (_) async {
            invites = await myInvites();
            notifyListeners();
          },
        )
        .subscribe();
  }

  /// Writes the person's own profile fields (column → value).
  Future<void> updateProfile(Map<String, Object?> fields) async {
    final me = myId;
    if (me == null || fields.isEmpty) return;
    await _db.from('profiles').update(fields).eq('id', me);
    await refresh();
  }

  Future<void> setPrivacy(String metric, MetricPrivacy v) async {
    final p = profile;
    if (p == null) return;
    final all = {
      for (final k in kPrivacyMetrics) k: p.privacyOf(k).toJson(),
      metric: v.toJson(),
    };
    await updateProfile({'privacy': all});
  }

  /// Puts up a profile photo (JPEG or PNG bytes); null takes it down.
  Future<void> setAvatar(Uint8List? image, {String mime = 'image/jpeg'}) async {
    final me = myId;
    if (me == null) return;
    final old = profile?.avatarPath;
    String? path;
    if (image != null) {
      path = '$me/${DateTime.now().millisecondsSinceEpoch}.'
          '${mime == 'image/png' ? 'png' : 'jpg'}';
      await _db.storage.from('avatars').uploadBinary(path, image,
          fileOptions: FileOptions(contentType: mime));
    }
    await updateProfile({'avatar_path': path});
    if (old != null) {
      unawaited(_db.storage.from('avatars').remove([old]).then((_) {}, onError: (_) {}));
    }
  }

  // ── teams ────────────────────────────────────────────────────────────────

  Future<TeamPreview?> previewByCode(String code) async {
    final r = await _db.rpc('team_preview', params: {'join_code': code});
    if (r is! List || r.isEmpty) return null;
    return TeamPreview.fromJson(r.first as Map<String, dynamic>);
  }

  Future<TeamPreview?> preview(String teamId) async {
    final r = await _db.rpc('team_preview', params: {'team': teamId});
    if (r is! List || r.isEmpty) return null;
    return TeamPreview.fromJson(r.first as Map<String, dynamic>);
  }

  /// Public teams, biggest first; [query] narrows by name.
  Future<List<TeamPreview>> publicTeams({String query = '', int limit = 30}) async {
    final r = await _db
        .rpc('public_teams', params: {'q': query.trim(), 'lim': limit});
    return [
      for (final j in r as List)
        TeamPreview.fromJson({...j as Map<String, dynamic>, 'is_public': true}),
    ];
  }

  Future<String> joinByCode(String code) async {
    final id = await _db.rpc('join_team', params: {'join_code': code});
    await refresh();
    return id as String;
  }

  Future<String> joinPublic(String teamId) async {
    final id = await _db.rpc('join_public', params: {'team': teamId});
    await refresh();
    return id as String;
  }

  // ── invites ──────────────────────────────────────────────────────────────

  Future<List<TeamInvite>> myInvites() async {
    try {
      final r = await _db.rpc('my_invites');
      return [for (final j in r as List) TeamInvite.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return const [];
    }
  }

  /// An admin asks [userId] into [teamId]; they join only by accepting.
  Future<void> inviteMember(String teamId, String userId) =>
      _db.rpc('invite_member', params: {'t': teamId, 'other': userId});

  /// Who has an open invitation to [teamId] (admins only).
  Future<Set<String>> invitees(String teamId) async {
    final r =
        await _db.from('team_invites').select('invitee').eq('team_id', teamId);
    return {for (final j in r) j['invitee'] as String};
  }

  Future<String> acceptInvite(String teamId) async {
    final id = await _db.rpc('accept_invite', params: {'t': teamId});
    await refresh();
    return id as String;
  }

  Future<void> declineInvite(String teamId) async {
    final me = myId;
    if (me == null) return;
    await _db
        .from('team_invites')
        .delete()
        .eq('team_id', teamId)
        .eq('invitee', me);
    invites = [for (final i in invites) if (i.team.id != teamId) i];
    notifyListeners();
  }

  Future<String> createTeam(NewTeam t) async {
    final id = await _db.rpc('create_team', params: {
      'team_name': t.name,
      'about': t.description,
      'public_team': t.isPublic,
      'chat': t.chat,
      'strain': t.boards.strain,
      'recovery': t.boards.recovery,
      'sleep': t.boards.sleep,
      'banner_key': t.banner,
      'logo_key': t.logo,
    }) as String;
    final fields = <String, Object?>{};
    if (t.bannerImage != null) {
      fields['banner'] = await _teamPicture(id, 'banner', t.bannerImage!);
    }
    if (t.logoImage != null) {
      fields['logo'] = await _teamPicture(id, 'logo', t.logoImage!);
    }
    if (fields.isNotEmpty) await _db.from('teams').update(fields).eq('id', id);
    await refresh();
    return id;
  }

  /// An uploaded team picture's reference: `storage:<path>`.
  Future<String> _teamPicture(String teamId, String what, Uint8List bytes) async {
    final path = '$teamId/$what-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage.from('teams').uploadBinary(path, bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'));
    return 'storage:$path';
  }

  /// An admin's edit: name, description, chat, banner, logo, public.
  Future<void> updateTeam(
    String teamId, {
    String? name,
    String? description,
    bool? chat,
    bool? isPublic,
    String? banner,
    String? logo,
    Uint8List? bannerImage,
    Uint8List? logoImage,
  }) async {
    await _db.from('teams').update({
      if (name != null) 'name': name.trim(),
      if (description != null) 'description': description.trim(),
      'chat_enabled': ?chat,
      'is_public': ?isPublic,
      'banner': bannerImage != null
          ? await _teamPicture(teamId, 'banner', bannerImage)
          : banner,
      'logo': logoImage != null ? await _teamPicture(teamId, 'logo', logoImage) : logo,
    }..removeWhere((_, v) => v == null)).eq('id', teamId);
    await refresh();
  }

  Future<void> leaveTeam(String teamId) async {
    final me = myId;
    if (me == null) return;
    await _db
        .from('team_members')
        .delete()
        .eq('team_id', teamId)
        .eq('user_id', me);
    await refresh();
  }

  /// The owner's way out: the team goes for everyone.
  Future<void> deleteTeam(String teamId) async {
    await _db.rpc('delete_team', params: {'team': teamId});
    await refresh();
  }

  Future<void> removeMember(String teamId, String userId) =>
      _db.rpc('remove_member', params: {'team': teamId, 'member': userId});

  Future<void> markRead(String teamId) async {
    final me = myId;
    if (me == null) return;
    teams = [for (final t in teams) t.id == teamId ? t.copyWith(unread: 0) : t];
    notifyListeners();
    await _db
        .from('team_members')
        .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('team_id', teamId)
        .eq('user_id', me);
  }

  /// My place in each team for [metric] over [from]–[to], by team id. A team
  /// where I have no figure in the window maps to null.
  Future<Map<String, ({int? rank, int of})>> myRanks(
      BoardMetric metric, DateTime from, DateTime to) async {
    final r = await _db.rpc('my_ranks', params: {
      'metric': metric.name,
      'since': dayLabelOf(from),
      'until': dayLabelOf(to),
    });
    return {
      for (final j in r as List)
        (j as Map)['team_id'] as String: (
          rank: (j['rank'] as num?)?.toInt(),
          of: (j['of_count'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  // ── a team's people and numbers ──────────────────────────────────────────

  Future<List<TeamPerson>> people(String teamId) async {
    final r = await _db.rpc('team_people', params: {'t': teamId});
    return [for (final j in r as List) TeamPerson.fromJson(j as Map<String, dynamic>)];
  }

  Future<List<DayScore>> scores(String teamId, DateTime from, DateTime to) async {
    final rows = await _db.rpc('team_scores', params: {
      't': teamId,
      'since': dayLabelOf(from),
      'until': dayLabelOf(to),
    });
    return [
      for (final r in rows as List)
        if (r is Map<String, dynamic> && !blocked.contains(r['user_id']))
          DayScore.fromJson(r),
    ];
  }

  Future<List<SharedActivity>> activities(
      String teamId, DateTime from, DateTime to) async {
    final rows = await _db.rpc('team_activities', params: {
      't': teamId,
      'since': dayLabelOf(from),
      'until': dayLabelOf(to),
    });
    return [
      for (final r in rows as List)
        if (r is Map<String, dynamic> && !blocked.contains(r['user_id']))
          SharedActivity.fromJson(r),
    ];
  }

  /// One person's days and workouts since [from], as I may see them.
  Future<({List<DayScore> days, List<SharedActivity> activities})> member(
      String userId, {DateTime? from}) async {
    final since = dayLabelOf(from ?? DateTime(2000));
    final d = await _db
        .rpc('member_scores', params: {'other': userId, 'since': since});
    final a = await _db
        .rpc('member_activities', params: {'other': userId, 'since': since});
    return (
      days: [
        for (final r in d as List)
          DayScore.fromJson({...r as Map<String, dynamic>, 'user_id': userId}),
      ],
      activities: [
        for (final r in a as List)
          SharedActivity.fromJson(r as Map<String, dynamic>, userId: userId),
      ],
    );
  }

  /// Works out which of the person's numbers some reader may see, and puts
  /// those up: every day on this phone the first time, the last month after.
  /// A metric nobody may see is taken back down.
  Future<void> uploadScores() async {
    final me = myId, p = profile, r = repo;
    if (me == null || p == null || r == null) return;
    bool want(String m) =>
        p.privacyOf(m).followers ||
        teams.any((t) => switch (m) {
              'strain' || 'activities' => t.boards.strain,
              'recovery' => t.boards.recovery,
              'sleep' => t.boards.sleep,
              _ => false,
            });
    final rec = want('recovery'), str = want('strain'), slp = want('sleep');
    final act = want('activities'), age = want('age');
    try {
      final full = !Prefs.getBool('community.uploaded_all.$me', false);
      final cutoff = full
          ? '0000-00-00'
          : dayLabelOf(DateTime.now().subtract(const Duration(days: 31)));
      // The figures as the app's own screens show them (dialSeries), so a
      // board never disagrees with the phone it came from.
      Future<Map<String, double>> series(String key, bool on) async {
        if (!on) return const {};
        final all = await dialSeries(r, key);
        return {
          for (final e in all.entries)
            if (e.key.compareTo(cutoff) >= 0) e.key: e.value,
        };
      }

      final recovery = await series('recovery', rec);
      final hrv = await series('hrv', rec), rhr = await series('resting_hr', rec);
      final strain = await series('strain', str);
      final calories = await series('calories', str);
      final tst = await series('tst_min', slp);
      final perf = await series('sleep_performance', slp);
      final hrMax = <String, double>{};
      if (str) {
        for (final row in await LocalDb.dayTrendFigures()) {
          final d = row['day'] as String?;
          if (d != null && d.compareTo(cutoff) >= 0 && row['hr_max'] is num) {
            hrMax[d] = (row['hr_max'] as num).toDouble();
          }
        }
      }
      final days = {
        ...recovery.keys, ...strain.keys, ...tst.keys, ...perf.keys,
      };
      final now = DateTime.now().toUtc().toIso8601String();
      final rows = [
        for (final d in days)
          {
            'user_id': me,
            'day': d,
            'recovery': recovery[d]?.round().clamp(0, 100),
            'hrv': hrv[d],
            'rhr': rhr[d],
            'strain': strain[d]?.clamp(0, 21),
            'calories': calories[d],
            'hr_max': hrMax[d]?.round(),
            'sleep_min': tst[d]?.round().clamp(0, 1440),
            'sleep_perf': perf[d]?.round().clamp(0, 100),
            'updated_at': now,
          },
      ];
      for (var i = 0; i < rows.length; i += 500) {
        await _db.from('daily_scores').upsert(
            rows.sublist(i, (i + 500).clamp(0, rows.length)));
      }
      if (age) {
        // Today's reading, and each finished week's (the Locus Age screen's
        // weekly points): half a year the first time, the last month after.
        // Its own batch, so the rows above keep every other column.
        final loader = TrendLoader(r);
        final today = todayLabel();
        final ages = <Map<String, Object?>>[];
        for (final d in [today, ...finishedSaturdays(today, full ? 26 : 5)]) {
          final v = (await loader.whoopAge(asOf: d)).whoopAge;
          if (v != null) {
            ages.add({'user_id': me, 'day': d, 'locus_age': v, 'updated_at': now});
          }
        }
        if (ages.isNotEmpty) await _db.from('daily_scores').upsert(ages);
      }
      // Whatever nobody may see any more comes down, every day of it.
      final cleared = {
        if (!rec) ...{'recovery': null, 'hrv': null, 'rhr': null},
        if (!str) ...{'strain': null, 'calories': null, 'hr_max': null},
        if (!slp) ...{'sleep_min': null, 'sleep_perf': null},
        if (!age) 'locus_age': null,
      };
      if (cleared.isNotEmpty) {
        await _db.from('daily_scores').update(cleared).eq('user_id', me);
      }
      if (act) {
        final sessions = await r.getSessions(
            from: 0,
            to: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            includeDetected: false);
        final up = [
          for (final s in sessions)
            if (s['end_ts'] != null &&
                s['start_ts'] is num &&
                s['private'] != 1 &&
                s['private'] != true)
              () {
                final at = DateTime.fromMillisecondsSinceEpoch(
                    (s['start_ts'] as num).toInt() * 1000);
                return {
                  'user_id': me,
                  'local_id': '${s['id'] ?? s['start_ts']}',
                  'day': dayLabelOf(at),
                  'started_at': at.toUtc().toIso8601String(),
                  'kind': '${s['type']}',
                  'strain': (s['strain'] as num?)?.toDouble(),
                  'calories': (s['calories'] as num?)?.toDouble(),
                };
              }(),
        ].where((m) => (m['day'] as String).compareTo(cutoff) >= 0).toList();
        for (var i = 0; i < up.length; i += 500) {
          await _db
              .from('activities')
              .upsert(up.sublist(i, (i + 500).clamp(0, up.length)));
        }
      } else {
        await _db.from('activities').delete().eq('user_id', me);
      }
      Prefs.setBool('community.uploaded_all.$me', true);
    } catch (e) {
      debugPrint('community scores: $e');
    }
  }

  // ── chat ─────────────────────────────────────────────────────────────────

  Future<List<ChatMessage>> messages(String teamId, {int limit = 80}) async {
    final rows = await _db
        .from('messages')
        .select()
        .eq('team_id', teamId)
        .order('created_at', ascending: false)
        .limit(limit);
    return [
      for (final r in rows.reversed)
        if (!blocked.contains(r['user_id'])) ChatMessage.fromJson(r),
    ];
  }

  /// Sends [body], with a picture ([image], PNG or JPEG bytes) when given.
  /// [card] names a shared card ('Daily overview').
  Future<void> send(String teamId, String body,
      {Uint8List? image, String? card, String mime = 'image/png'}) async {
    final me = myId;
    final text = body.trim();
    if (me == null || (text.isEmpty && image == null)) return;
    String? path;
    if (image != null) {
      final ext = mime == 'image/jpeg' ? 'jpg' : 'png';
      path = '$teamId/$me/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _db.storage.from('posts').uploadBinary(path, image,
          fileOptions: FileOptions(contentType: mime));
    }
    await _db.from('messages').insert({
      'team_id': teamId,
      'user_id': me,
      'body': text,
      'image_path': ?path,
      'card': ?card,
    });
  }

  Future<void> deleteMessage(ChatMessage m) async {
    await _db.from('messages').delete().eq('id', m.id);
    if (m.imagePath != null) {
      await _db.storage.from('posts').remove([m.imagePath!]);
    }
  }

  final _urls = <String, (String, DateTime)>{};

  /// A short-lived link to a picture in [bucket], kept for most of its hour.
  Future<String> pictureUrl(String path, {String bucket = 'posts'}) async {
    final key = '$bucket/$path';
    final hit = _urls[key];
    if (hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
    final url = await _db.storage.from(bucket).createSignedUrl(path, 3600);
    _urls[key] = (url, DateTime.now().add(const Duration(minutes: 50)));
    return url;
  }

  // ── humans ───────────────────────────────────────────────────────────────

  Future<List<Human>> search(String query) async {
    if (query.trim().length < 2) return const [];
    final r = await _db.rpc('search_profiles', params: {'q': query});
    return [for (final j in r as List) Human.fromJson(j as Map<String, dynamic>)];
  }

  Future<Human?> human(String userId) async {
    final r = await _db.rpc('profile_card', params: {'other': userId});
    if (r is! List || r.isEmpty) return null;
    return Human.fromJson(r.first as Map<String, dynamic>);
  }

  /// [which] is 'followers' or 'following'. Mine include pending requests.
  Future<List<Human>> followList(String userId, String which) async {
    final r = await _db
        .rpc('follow_list', params: {'other': userId, 'which': which});
    return [for (final j in r as List) Human.fromJson(j as Map<String, dynamic>)];
  }

  Future<List<Human>> followRequests() async {
    final me = myId;
    if (me == null) return const [];
    try {
      final all = await followList(me, 'followers');
      return [for (final h in all) if (h.requested) h];
    } catch (_) {
      return const [];
    }
  }

  /// Asks to follow; returns 'pending' or 'accepted'.
  Future<String?> follow(String userId) async {
    final r = await _db.rpc('follow', params: {'other': userId});
    notifyListeners();
    return r as String?;
  }

  Future<void> unfollow(String userId) async {
    final me = myId;
    if (me == null) return;
    await _db.from('follows').delete().eq('follower', me).eq('followee', userId);
    notifyListeners();
  }

  Future<void> accept(String userId) async {
    await _db.rpc('accept_follow', params: {'requester': userId});
    requests = [for (final h in requests) if (h.id != userId) h];
    notifyListeners();
  }

  /// Declines a request, or removes a follower.
  Future<void> removeFollower(String userId) async {
    final me = myId;
    if (me == null) return;
    await _db.from('follows').delete().eq('follower', userId).eq('followee', me);
    requests = [for (final h in requests) if (h.id != userId) h];
    notifyListeners();
  }

  // ── safety ───────────────────────────────────────────────────────────────

  Future<void> report(
      {String? teamId, int? messageId, String reason = ''}) async {
    final me = myId;
    if (me == null) return;
    await _db.from('reports').insert({
      'reporter': me,
      'team_id': ?teamId,
      'message_id': ?messageId,
      'reason': reason,
    });
  }

  Future<void> block(String userId) async {
    final me = myId;
    if (me == null || userId == me) return;
    await _db.from('blocks').upsert({'blocker': me, 'blocked': userId});
    blocked = {...blocked, userId};
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _messages.close();
    super.dispose();
  }
}
