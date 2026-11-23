// Community snapshots: the community pages with a made-up team, people and
// scores, tapped through and written out as PNGs to set beside the reference
// screens. A camera, not a golden: off by default, kept out of CI.
//
//   SNAPSHOTS=1 flutter test test/community_snapshots_test.dart
//
// Output: build/design_snapshots/community/<page>.png. Anything a page throws
// goes to errors.txt there instead of failing the run.
@Tags(['snapshots'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/community/community_service.dart';
import 'package:openstrap_edge/community/leaderboard.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/community/community.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = Size(390, 844);
const _ratio = 2.0;
final _shot = GlobalKey();

DateTime _day(int back) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day - back);
}

const _people = [
  TeamPerson('me', 'Vince Papp', role: 'owner', username: 'vince', hue: 200),
  TeamPerson('u1', 'Ana Lopez', username: 'ana.runs', hue: 20),
  TeamPerson('u2', 'Marco Rossi', username: 'marco', hue: 140),
  TeamPerson('u3', 'Jade Kim', role: 'admin', username: 'jadek', hue: 280),
  TeamPerson('u4', 'Tom Becker', username: 'tomb', hue: 60),
  TeamPerson('u5', 'Lea Novak', username: 'lea', hue: 320),
  TeamPerson('u6', 'Sam Reed', hue: 100),
];

/// A stand-in that answers every call from the data above.
class _FakeCommunity extends CommunityService {
  _FakeCommunity({this.signedInNow = true}) : super.forTest() {
    profile = const CommunityProfile('me', 'Vince Papp',
        hue: 200, username: 'vince', birthYear: 1994, region: 'Budapest');
    teams = signedInNow ? [_crew, _club] : const [];
    requests = [_h('u5', 'Lea Novak', 'lea', 320, state: 'pending')];
  }

  final bool signedInNow;
  bool withTeams = true;

  static final _crew = CommunityTeam('t1', 'Morning Crew', 'MRN42X',
      role: 'owner',
      chatEnabled: true,
      description: 'Up before seven, five days a week. Post your rings.',
      banner: 'banner_3',
      logo: 'medal',
      lastReadAt: DateTime(2026),
      unread: 3,
      members: 7);
  static final _club = CommunityTeam('t2', 'Budapest Runners', 'BUD777',
      isPublic: true,
      banner: 'banner_6',
      logo: 'target',
      boards: const Boards(sleep: false),
      lastReadAt: DateTime(2026),
      members: 1284);

  Human _h(String id, String name, String? user, int hue,
          {String? state, bool followsMe = false}) =>
      Human(id, name,
          username: user,
          hue: hue,
          birthYear: 1990,
          region: 'Budapest',
          followers: 41,
          following: 38,
          memberSince: DateTime(2025, 3),
          followState: state,
          followsMe: followsMe);

  List<DayScore> _scores(String user, int seed) => [
        for (var i = 0; i < 35; i++)
          DayScore(user, _day(i),
              recovery: (30 + (seed * 13 + i * 7) % 68).toDouble(),
              strain: 6 + ((seed * 5 + i * 3) % 140) / 10,
              sleepMin: 380 + ((seed * 17 + i * 11) % 120).toDouble(),
              sleepPerf: (62 + (seed * 7 + i * 5) % 37).toDouble(),
              hrv: 40 + ((seed * 3 + i) % 50).toDouble(),
              rhr: 48 + ((seed + i) % 14).toDouble(),
              calories: 1900 + ((seed * 97 + i * 31) % 1400).toDouble(),
              hrMax: 150 + ((seed + i * 3) % 40).toDouble()),
      ];

  @override
  bool get ready => true;
  @override
  bool get signedIn => signedInNow;
  @override
  String? get myId => signedInNow ? 'me' : null;
  @override
  bool get anonymous => true;
  @override
  Future<void> ensureReady() async {}
  @override
  Future<void> refresh() async {
    teams = withTeams && signedInNow ? [_crew, _club] : const [];
  }

  @override
  Future<List<TeamPreview>> publicTeams({String query = '', int limit = 30}) async => [
        for (final (i, n) in ['Iron Lungs', 'Sleep Club', 'Trail Mix', '5AM Lifters']
            .indexed)
          TeamPreview('p$i', n,
              banner: 'banner_${i + 7}',
              logo: ['flame', 'moon', 'mountain', 'dumbbell'][i],
              isPublic: true,
              members: [3120, 845, 12400, 290][i]),
      ];
  @override
  Future<Map<String, ({int? rank, int of})>> myRanks(
          BoardMetric metric, DateTime from, DateTime to) async =>
      {'t1': (rank: 2, of: 7), 't2': (rank: 214, of: 1284)};
  @override
  Future<TeamPreview?> previewByCode(String code) async => const TeamPreview(
      't9', 'Office Steps',
      description: 'The fourth floor against the fifth. Loser buys coffee.',
      banner: 'banner_2',
      logo: 'trophy',
      chatEnabled: true,
      members: 23);
  @override
  Future<List<TeamPerson>> people(String teamId) async => _people;
  @override
  Future<List<DayScore>> scores(String teamId, DateTime from, DateTime to) async => [
        for (final (i, p) in _people.indexed)
          for (final d in _scores(p.id, i))
            if (!d.day.isBefore(from) && !d.day.isAfter(to)) d,
      ];
  @override
  Future<List<SharedActivity>> activities(
          String teamId, DateTime from, DateTime to) async =>
      [
        SharedActivity('u1', _day(0), _day(0).add(const Duration(hours: 7)),
            'Running', strain: 12.4, calories: 640),
        SharedActivity('me', _day(0), _day(0).add(const Duration(hours: 18)),
            'Weightlifting', strain: 9.1, calories: 410),
      ];
  @override
  Future<({List<DayScore> days, List<SharedActivity> activities})> member(
          String userId, {DateTime? from}) async =>
      (
        days: _scores(userId, userId.hashCode % 9),
        activities: [
          for (var i = 0; i < 12; i++)
            SharedActivity(userId, _day(i * 2),
                _day(i * 2).add(const Duration(hours: 7)),
                ['Running', 'Cycling', 'Weightlifting'][i % 3],
                strain: 8 + i % 7, calories: 400 + i * 20),
        ],
      );
  @override
  Future<Human?> human(String userId) async {
    final p = _people.firstWhere((x) => x.id == userId, orElse: () => _people[1]);
    return _h(p.id, p.name, p.username, p.hue, state: 'accepted', followsMe: true);
  }

  @override
  Future<List<Human>> followList(String userId, String which) async => which ==
          'following'
      ? [
          _h('u1', 'Ana Lopez', 'ana.runs', 20, state: 'accepted'),
          _h('u2', 'Marco Rossi', 'marco', 140, state: 'accepted'),
          _h('u3', 'Jade Kim', 'jadek', 280, state: 'accepted'),
        ]
      : [
          _h('u5', 'Lea Novak', 'lea', 320, state: 'pending'),
          _h('u1', 'Ana Lopez', 'ana.runs', 20, state: 'accepted'),
          _h('u4', 'Tom Becker', 'tomb', 60, state: 'accepted'),
        ];
  @override
  Future<List<Human>> search(String query) async => [
        _h('u1', 'Ana Lopez', 'ana.runs', 20, state: 'accepted'),
        _h('u7', 'Anna Varga', 'annav', 170),
        _h('u8', 'Andras Toth', null, 230, state: 'pending'),
        _h('u9', 'Danny Ng', 'dng', 10, followsMe: true),
      ];
  @override
  Future<List<ChatMessage>> messages(String teamId, {int limit = 80}) async => [
        ChatMessage(1, teamId, 'u1', 'Who is in for the 6am loop tomorrow?',
            _day(1).add(const Duration(hours: 21, minutes: 4))),
        ChatMessage(2, teamId, 'u3', 'Me. Recovery is green for once.',
            _day(1).add(const Duration(hours: 21, minutes: 9))),
        ChatMessage(3, teamId, 'me', 'Count me in 👟',
            _day(0).add(const Duration(hours: 6, minutes: 12))),
        ChatMessage(4, teamId, 'u2', 'Strain 14 before breakfast, you all are animals',
            _day(0).add(const Duration(hours: 8, minutes: 40))),
      ];
  @override
  Future<void> markRead(String teamId) async {}
  @override
  Future<void> uploadScores() async {}
}

Future<void> _loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    for (final name in [family, if (family == 'Manrope') '.SF Pro Text']) {
      final loader = FontLoader(name);
      for (final f in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(f['asset'] as String));
      }
      await loader.load();
    }
  }
}

Widget _app(Widget home) => MediaQuery(
      data: const MediaQueryData(
          size: _phone, padding: EdgeInsets.only(top: 47, bottom: 34)),
      child: RepaintBoundary(
        key: _shot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: home,
        ),
      ),
    );

void main() {
  final skip = Platform.environment['SNAPSHOTS'] != '1'
      ? 'set SNAPSHOTS=1 to write community snapshots'
      : null;
  final dir = Directory('build/design_snapshots/community');
  final errors = <String>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    if (skip == null) {
      await _loadFonts();
      dir.createSync(recursive: true);
    }
  });
  tearDownAll(() {
    if (skip == null) File('${dir.path}/errors.txt').writeAsStringSync(errors.join('\n'));
  });

  Future<void> settle(WidgetTester t, [int frames = 8]) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    // Decode the pictures on screen, then let them paint.
    await t.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        final img = e.widget as Image;
        try {
          await precacheImage(img.image, e);
        } catch (_) {}
      }
    });
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    await settle(t);
    final b = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final png = await t.runAsync(() async {
      final image = await b.toImage(pixelRatio: _ratio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes!.buffer.asUint8List();
    });
    File('${dir.path}/$name.png').writeAsBytesSync(png ?? Uint8List(0));
  }

  Finder? find1(String s) {
    for (final f in [
      find.bySemanticsLabel(s),
      find.text(s),
      find.text(s.toUpperCase()),
      find.textContaining(s),
      find.textContaining(s.toUpperCase()),
    ]) {
      if (f.evaluate().isNotEmpty) return f.first;
    }
    return null;
  }

  Future<void> tap(WidgetTester t, String s) async {
    var f = find1(s);
    // Lists build lazily: scroll down until it is there.
    for (var i = 0; f == null && i < 8; i++) {
      final sc = find.byType(Scrollable);
      if (sc.evaluate().isEmpty) break;
      await t.drag(sc.first, const Offset(0, -300), warnIfMissed: false);
      await settle(t, 2);
      f = find1(s);
    }
    if (f == null) throw StateError('nothing called "$s" on screen');
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f, warnIfMissed: false);
    await settle(t, 6);
  }

  Future<void> run(WidgetTester t, String name, _FakeCommunity svc,
      Future<void> Function() steps) async {
    t.view.physicalSize = _phone * _ratio;
    t.view.devicePixelRatio = _ratio;
    addTearDown(t.view.reset);
    CommunityService.debugInstance = svc;
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add('$name: ${d.exceptionAsString().split('\n').first}');
    try {
      await steps();
    } catch (e) {
      errors.add('$name: $e');
    } finally {
      FlutterError.onError = previous;
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
    }
  }

  testWidgets('community pages', skip: skip != null, (t) async {
    await run(t, 'intro', _FakeCommunity(signedInNow: false), () async {
      await t.pumpWidget(_app(const CommunityScreen(tab: true)));
      await shot(t, '00_intro_1');
      await tap(t, 'Next');
      await shot(t, '00_intro_2');
      await tap(t, 'Next');
      await shot(t, '00_intro_3');
      await tap(t, 'Next');
      await shot(t, '00_intro_4');
    });

    await run(t, 'home empty', _FakeCommunity()..withTeams = false, () async {
      await t.pumpWidget(_app(const CommunityScreen(tab: true)));
      await shot(t, '01_home_empty');
    });

    await run(t, 'home', _FakeCommunity(), () async {
      await t.pumpWidget(_app(const CommunityScreen(tab: true)));
      await shot(t, '02_home');
      await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await shot(t, '02_home_scrolled');
      await tap(t, 'Choose how ranks show');
      await shot(t, '03_rank_display');
    });

    await run(t, 'join', _FakeCommunity(), () async {
      await t.pumpWidget(_app(const CommunityScreen(tab: true)));
      await settle(t);
      await tap(t, 'Enter code');
      await shot(t, '10_join_code');
      await t.enterText(find.byType(EditableText).first, 'OFF1CE');
      await settle(t, 2);
      await shot(t, '11_join_code_typed');
      await tap(t, 'Submit code');
      await settle(t, 10);
      await shot(t, '12_team_details');
    });

    await run(t, 'create', _FakeCommunity(), () async {
      await t.pumpWidget(_app(const CommunityScreen(tab: true)));
      await settle(t);
      await tap(t, 'Create team');
      await shot(t, '20_create_name');
      await t.enterText(find.byType(EditableText).first, 'Night Owls');
      await settle(t, 2);
      await shot(t, '21_create_name_typed');
      await tap(t, 'NEXT');
      await shot(t, '22_create_banner');
      await tap(t, 'NEXT');
      await shot(t, '23_create_logo');
      await tap(t, 'NEXT');
      await shot(t, '24_create_boards');
    });

    await run(t, 'team', _FakeCommunity(), () async {
      await t.pumpWidget(_app(const CommunityScreen(tab: true)));
      await settle(t);
      await tap(t, 'Morning Crew');
      await shot(t, '30_team_board_strain');
      await tap(t, 'info');
      await shot(t, '31_team_info');
      await tap(t, 'chat');
      await shot(t, '32_team_chat');
      await tap(t, 'recovery');
      await shot(t, '33_team_board_recovery');
      await tap(t, 'sleep');
      await shot(t, '34_team_board_sleep');
      await tap(t, 'Filter');
      await shot(t, '35_board_filter');
    });

    await run(t, 'team menu', _FakeCommunity(), () async {
      await t.pumpWidget(_app(const CommunityScreen(tab: true)));
      await settle(t);
      await tap(t, 'Morning Crew');
      await tap(t, 'Team options');
      await shot(t, '36_team_menu');
      await tap(t, 'Manage team');
      await shot(t, '37_manage_team');
    });

    await run(t, 'share data', _FakeCommunity(), () async {
      await t.pumpWidget(_app(const CommunityScreen(tab: true)));
      await settle(t);
      await tap(t, 'Morning Crew');
      await tap(t, 'chat');
      await tap(t, 'Data');
      await shot(t, '38_share_data');
    });

    await run(t, 'humans', _FakeCommunity(), () async {
      await t.pumpWidget(_app(const CommunityScreen(tab: true)));
      await settle(t);
      await tap(t, 'Humans');
      await shot(t, '40_humans_following');
      await tap(t, 'Followers (');
      await shot(t, '41_humans_followers');
      await tap(t, 'Following (');
      await tap(t, 'Ana Lopez');
      await shot(t, '42_member_profile');
      await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await shot(t, '43_member_profile_scrolled');
    });

    await run(t, 'search', _FakeCommunity(), () async {
      await t.pumpWidget(_app(const CommunityScreen(tab: true)));
      await settle(t);
      await tap(t, 'Search members');
      await t.enterText(find.byType(EditableText).first, 'an');
      await t.pump(const Duration(seconds: 1));
      await shot(t, '44_search_members');
    });

    await run(t, 'privacy', _FakeCommunity(), () async {
      await t.pumpWidget(_app(const CommunityScreen(tab: true)));
      await settle(t);
      await tap(t, 'Privacy');
      await shot(t, '50_privacy');
      await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await shot(t, '51_privacy_scrolled');
      await tap(t, 'Sleep');
      await shot(t, '52_privacy_sleep_sheet');
    });

    await run(t, 'explore', _FakeCommunity(), () async {
      await t.pumpWidget(_app(const CommunityScreen(tab: true)));
      await settle(t);
      await tap(t, 'Search for teams');
      await shot(t, '60_explore_teams');
    });
  });
}
