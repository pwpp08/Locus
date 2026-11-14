// The community's one door to the server: sign-in, the person's profile and
// what they share, their teams, the leaderboard's numbers, team chat and the
// team feed.
//
// LOCAL FIRST STILL HOLDS. Nothing here touches the network until the person
// opens the community and signs in: the client is not even started at launch
// for someone who never has ([resumeIfUsed]). Signed in, what leaves the phone
// is a display name, a colour, and one number a day for each metric they
// ticked under "What I share" — everything off until they tick it.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/day_label.dart';
import '../data/db.dart';
import '../state/prefs.dart';
import 'leaderboard.dart';

/// The project the app talks to. The publishable key is meant to ship in the
/// app: row level security on the server decides what each person can read.
const String kCommunityUrl = 'https://oyxjhxrlgrexbsvyohzv.supabase.co';
const String kCommunityKey = 'sb_publishable_m5WqPpPZTDNVszvJO_XTYw_lsSWYIIZ';

/// Where Google sends the person back to after they sign in.
const String kCommunityRedirect = 'wtf.openstrap.openstrap_edge://login-callback';

class CommunityProfile {
  final String id, name;
  final int hue;
  final bool shareRecovery, shareStrain, shareSleep;
  const CommunityProfile(this.id, this.name,
      {this.hue = 0,
      this.shareRecovery = false,
      this.shareStrain = false,
      this.shareSleep = false});

  factory CommunityProfile.fromJson(Map<String, dynamic> j) => CommunityProfile(
        j['id'] as String,
        (j['display_name'] as String?) ?? 'Member',
        hue: (j['hue'] as num?)?.toInt() ?? 0,
        shareRecovery: j['share_recovery'] == true,
        shareStrain: j['share_strain'] == true,
        shareSleep: j['share_sleep'] == true,
      );

  bool get sharesAnything => shareRecovery || shareStrain || shareSleep;
}

class CommunityTeam {
  final String id, name, code, role;
  final bool isOpen;
  final DateTime lastReadAt;
  final int unread;
  const CommunityTeam(this.id, this.name, this.code,
      {this.isOpen = false,
      this.role = 'member',
      required this.lastReadAt,
      this.unread = 0});

  CommunityTeam withUnread(int n) => CommunityTeam(id, name, code,
      isOpen: isOpen, role: role, lastReadAt: lastReadAt, unread: n);
}

class ChatMessage {
  final int id;
  final String teamId, userId, body;
  final DateTime at;
  const ChatMessage(this.id, this.teamId, this.userId, this.body, this.at);

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        (j['id'] as num).toInt(),
        j['team_id'] as String,
        j['user_id'] as String,
        j['body'] as String,
        DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

class FeedPost {
  final int id;
  final String teamId, userId, caption, imagePath;
  final DateTime at;
  const FeedPost(this.id, this.teamId, this.userId, this.caption,
      this.imagePath, this.at);

  factory FeedPost.fromJson(Map<String, dynamic> j) => FeedPost(
        (j['id'] as num).toInt(),
        j['team_id'] as String,
        j['user_id'] as String,
        (j['caption'] as String?) ?? '',
        j['image_path'] as String,
        DateTime.parse(j['created_at'] as String).toLocal(),
      );
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
  static final CommunityService instance = CommunityService._();

  /// Set once the person has signed in on this phone: from then on the
  /// client starts at launch, so the badge and the scores keep up.
  static const String kUsed = 'community.used';

  bool _ready = false;
  Future<void>? _starting;
  StreamSubscription<AuthState>? _authSub;
  RealtimeChannel? _channel;

  SupabaseClient get _db => Supabase.instance.client;

  bool get ready => _ready;
  User? get user => _ready ? _db.auth.currentUser : null;
  bool get signedIn => user != null;
  String? get myId => user?.id;

  CommunityProfile? profile;
  List<CommunityTeam> teams = const [];
  Set<String> blocked = const {};

  /// The team whose chat is on screen: its new messages are not unread.
  String? viewingChat;

  int get unread => teams.fold(0, (n, t) => n + t.unread);

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
    _channel?.unsubscribe();
    _channel = null;
    notifyListeners();
  }

  // ── sign in ──────────────────────────────────────────────────────────────

  Future<void> sendCode(String email) async {
    await ensureReady();
    await _db.auth.signInWithOtp(
        email: email.trim(), shouldCreateUser: true, emailRedirectTo: null);
  }

  Future<void> verifyCode(String email, String code) async {
    await ensureReady();
    await _db.auth.verifyOTP(
        type: OtpType.email, email: email.trim(), token: code.trim());
    Prefs.setBool(kUsed, true);
    await refresh();
  }

  /// Whether Google sign-in is switched on in the project. The button only
  /// shows when it is, so it never leads to "provider is not enabled".
  Future<bool> googleAvailable() async {
    try {
      final r = await http.get(Uri.parse('$kCommunityUrl/auth/v1/settings'),
          headers: {'apikey': kCommunityKey}).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return false;
      final j = jsonDecode(r.body);
      return j is Map && j['external'] is Map && j['external']['google'] == true;
    } catch (_) {
      return false;
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
      final p = await _db.from('profiles').select().eq('id', me).maybeSingle();
      profile = p == null ? null : CommunityProfile.fromJson(p);
      final rows = await _db
          .from('team_members')
          .select('role, last_read_at, teams(id, name, code, is_open)')
          .eq('user_id', me);
      final list = <CommunityTeam>[];
      for (final r in rows) {
        final t = r['teams'];
        if (t is! Map) continue;
        list.add(CommunityTeam(
          t['id'] as String,
          t['name'] as String,
          t['code'] as String,
          isOpen: t['is_open'] == true,
          role: (r['role'] as String?) ?? 'member',
          lastReadAt: DateTime.parse(r['last_read_at'] as String),
        ));
      }
      // Your own teams first, by name; the open community last.
      list.sort((a, b) => a.isOpen != b.isOpen
          ? (a.isOpen ? 1 : -1)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final b = await _db.from('blocks').select('blocked').eq('blocker', me);
      blocked = {for (final r in b) r['blocked'] as String};
      teams = await _withUnread(list);
      _listen();
      notifyListeners();
      unawaited(uploadScores());
    } catch (e) {
      debugPrint('community refresh: $e');
    }
  }

  /// Each team's count of messages and posts newer than its last read, not
  /// counting the person's own or anyone they blocked.
  Future<List<CommunityTeam>> _withUnread(List<CommunityTeam> list) async {
    final me = myId;
    final out = <CommunityTeam>[];
    for (final t in list) {
      if (t.isOpen || me == null) {
        out.add(t);
        continue;
      }
      final since = t.lastReadAt.toUtc().toIso8601String();
      var n = 0;
      for (final table in ['messages', 'posts']) {
        final rows = await _db
            .from(table)
            .select('user_id')
            .eq('team_id', t.id)
            .gt('created_at', since)
            .neq('user_id', me)
            .limit(100);
        n += rows.where((r) => !blocked.contains(r['user_id'])).length;
      }
      out.add(t.withUnread(n));
    }
    return out;
  }

  /// One live subscription to new chat messages; the server only sends the
  /// ones from the person's own teams.
  void _listen() {
    if (_channel != null) return;
    _channel = _db
        .channel('community-messages')
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
              for (final t in teams) t.id == m.teamId ? t.withUnread(t.unread + 1) : t,
            ];
            notifyListeners();
          },
        )
        .subscribe();
  }

  Future<void> updateProfile({
    String? name,
    int? hue,
    bool? shareRecovery,
    bool? shareStrain,
    bool? shareSleep,
  }) async {
    final me = myId;
    if (me == null) return;
    await _db.from('profiles').update({
      if (name != null) 'display_name': name.trim(),
      'hue': ?hue,
      'share_recovery': ?shareRecovery,
      'share_strain': ?shareStrain,
      'share_sleep': ?shareSleep,
    }).eq('id', me);
    // Unticked: what was already up there goes too, not just tomorrow's.
    final cleared = {
      if (shareRecovery == false) 'recovery': null,
      if (shareStrain == false) 'strain': null,
      if (shareSleep == false) 'sleep_min': null,
    };
    if (cleared.isNotEmpty) {
      await _db.from('daily_scores').update(cleared).eq('user_id', me);
    }
    await refresh();
  }

  Future<String> createTeam(String name) async {
    final id = await _db.rpc('create_team', params: {'team_name': name});
    await refresh();
    return id as String;
  }

  Future<String> joinTeam(String code) async {
    final id = await _db.rpc('join_team', params: {'join_code': code});
    await refresh();
    return id as String;
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

  bool get inOpenCommunity => teams.any((t) => t.isOpen);

  Future<void> setOpenCommunity(bool on) async {
    if (on) {
      await joinTeam('OPEN');
    } else {
      final open = teams.where((t) => t.isOpen).firstOrNull;
      if (open != null) await leaveTeam(open.id);
    }
  }

  Future<void> markRead(String teamId) async {
    final me = myId;
    if (me == null) return;
    teams = [for (final t in teams) t.id == teamId ? t.withUnread(0) : t];
    notifyListeners();
    await _db
        .from('team_members')
        .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('team_id', teamId)
        .eq('user_id', me);
  }

  // ── a team's people and numbers ──────────────────────────────────────────

  Future<Map<String, CommunityProfile>> members(String teamId) async {
    final rows = await _db
        .from('team_members')
        .select('user_id')
        .eq('team_id', teamId);
    final ids = [for (final r in rows) r['user_id'] as String];
    if (ids.isEmpty) return const {};
    final ps = await _db.from('profiles').select().inFilter('id', ids);
    return {
      for (final p in ps)
        if (!blocked.contains(p['id'])) p['id'] as String: CommunityProfile.fromJson(p),
    };
  }

  Future<List<DayScore>> scores(String teamId, {int days = 30}) async {
    final since = DateTime.now().subtract(Duration(days: days + 1));
    final rows = await _db.rpc('team_scores',
        params: {'t': teamId, 'since': dayLabelOf(since)});
    return [
      for (final r in rows as List)
        if (r is Map<String, dynamic> && !blocked.contains(r['user_id']))
          DayScore.fromJson(r),
    ];
  }

  /// Puts the last month's shared numbers up: one row a day, the metrics the
  /// person did not tick sent as nothing at all.
  Future<void> uploadScores() async {
    final me = myId, p = profile;
    if (me == null || p == null || !p.sharesAnything) return;
    try {
      final cutoff = dayLabelOf(DateTime.now().subtract(const Duration(days: 31)));
      Future<Map<String, double>> series(String key, bool on) async {
        if (!on) return const {};
        final rows = await LocalDb.metricSeries(key, measuredOnly: true);
        return {
          for (final r in rows)
            if ((r['date'] as String).compareTo(cutoff) >= 0)
              r['date'] as String: (r['value'] as num).toDouble(),
        };
      }

      final rec = await series('readiness', p.shareRecovery);
      final str = await series('strain', p.shareStrain);
      final slp = await series('tst_min', p.shareSleep);
      final days = {...rec.keys, ...str.keys, ...slp.keys};
      if (days.isEmpty) return;
      await _db.from('daily_scores').upsert([
        for (final d in days)
          {
            'user_id': me,
            'day': d,
            'recovery': rec[d]?.round().clamp(0, 100),
            'strain': str[d]?.clamp(0, 21),
            'sleep_min': slp[d]?.round().clamp(0, 1440),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
      ]);
    } catch (e) {
      debugPrint('community scores: $e');
    }
  }

  // ── chat ─────────────────────────────────────────────────────────────────

  Future<List<ChatMessage>> messages(String teamId, {int limit = 60}) async {
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

  Future<void> send(String teamId, String body) async {
    final me = myId;
    final text = body.trim();
    if (me == null || text.isEmpty) return;
    await _db
        .from('messages')
        .insert({'team_id': teamId, 'user_id': me, 'body': text});
  }

  Future<void> deleteMessage(int id) =>
      _db.from('messages').delete().eq('id', id);

  // ── feed ─────────────────────────────────────────────────────────────────

  Future<List<FeedPost>> posts(String teamId, {int limit = 40}) async {
    final rows = await _db
        .from('posts')
        .select()
        .eq('team_id', teamId)
        .order('created_at', ascending: false)
        .limit(limit);
    return [
      for (final r in rows)
        if (!blocked.contains(r['user_id'])) FeedPost.fromJson(r),
    ];
  }

  /// Posts [image] (PNG or JPEG bytes) with [caption] to each of [teamIds].
  Future<void> post(List<String> teamIds, Uint8List image, String caption,
      {String mime = 'image/png'}) async {
    final me = myId;
    if (me == null) return;
    final ext = mime == 'image/jpeg' ? 'jpg' : 'png';
    for (final t in teamIds) {
      final path = '$t/$me/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _db.storage.from('posts').uploadBinary(path, image,
          fileOptions: FileOptions(contentType: mime));
      await _db.from('posts').insert({
        'team_id': t,
        'user_id': me,
        'caption': caption.trim(),
        'image_path': path,
      });
    }
  }

  Future<void> deletePost(FeedPost p) async {
    await _db.from('posts').delete().eq('id', p.id);
    await _db.storage.from('posts').remove([p.imagePath]);
  }

  final _urls = <String, (String, DateTime)>{};

  /// A short-lived link to a feed picture, kept for most of its hour.
  Future<String> pictureUrl(String path) async {
    final hit = _urls[path];
    if (hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
    final url = await _db.storage.from('posts').createSignedUrl(path, 3600);
    _urls[path] = (url, DateTime.now().add(const Duration(minutes: 50)));
    return url;
  }

  // ── safety ───────────────────────────────────────────────────────────────

  Future<void> report(
      {String? teamId, int? messageId, int? postId, String reason = ''}) async {
    final me = myId;
    if (me == null) return;
    await _db.from('reports').insert({
      'reporter': me,
      'team_id': ?teamId,
      'message_id': ?messageId,
      'post_id': ?postId,
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
