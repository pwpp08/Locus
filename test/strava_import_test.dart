// Strava: the sign-in link is checked before it is trusted, activities become
// labelled imported workouts, and an expired token is refreshed.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/import/strava_import.dart';

class _Mem implements TokenStore {
  final m = <String, String>{};
  @override
  Future<String?> read(String k) async => m[k];
  @override
  Future<void> write(String k, String v) async => m[k] = v;
  @override
  Future<void> delete(String k) async => m.remove(k);
}

Uri _cb(String state, {String code = 'abc', String scope = 'read,activity:read'}) =>
    Uri.parse('wtf.openstrap.locus://strava-callback?state=$state&code=$code&scope=$scope');

void main() {
  group('callback link', () {
    test('a good link gives its code', () {
      expect(parseStravaCallback(_cb('s1'), 's1')?.code, 'abc');
    });
    test('another state, another host, or no activity permission is not accepted', () {
      expect(parseStravaCallback(_cb('other'), 's1'), isNull);
      expect(
          parseStravaCallback(Uri.parse('wtf.openstrap.locus://login-callback?code=x&state=s1'), 's1'),
          isNull);
      final r = parseStravaCallback(_cb('s1', scope: 'read'), 's1')!;
      expect(r.code, isNull);
      expect(r.error, contains('activities'));
    });
    test('the person declining is reported', () {
      final r = parseStravaCallback(
          Uri.parse('wtf.openstrap.locus://strava-callback?state=s1&error=access_denied'),
          's1')!;
      expect(r.error, contains('access_denied'));
    });
  });

  group('activities', () {
    test('kinds read like the health store\'s, bad rows are dropped', () {
      final rows = stravaRowsFrom([
        {'id': 1, 'start_date': '2026-11-20T07:00:00Z', 'elapsed_time': 3600,
         'sport_type': 'TrailRun', 'distance': 10250.5, 'kilojoules': 900},
        {'id': 2, 'start_date': '2026-11-21T07:00:00Z', 'elapsed_time': 1800,
         'type': 'Ride', 'distance': 0},
        {'id': 3, 'start_date': '2026-11-21T07:00:00Z', 'elapsed_time': 0},
        {'start_date': '2026-11-21T07:00:00Z', 'elapsed_time': 600},
        'not a map',
      ]);
      expect(rows.map((r) => r.uuid), ['strava:1', 'strava:2']);
      expect(rows[0].kind, 'TRAIL_RUN');
      expect(rows[0].source, 'Strava');
      expect(rows[0].distanceM, 10250.5);
      expect(rows[0].energyKcal, isNull, reason: 'kJ of work is not calories');
      expect(rows[0].endTs - rows[0].startTs, 3600);
      expect(rows[1].distanceM, isNull, reason: 'zero is absent, not a distance');
    });
  });

  group('account', () {
    late Directory dir;
    setUp(() async {
      databaseFactory = databaseFactoryFfi;
      LocalDb.dbName = 'openstrap_strava_test.db';
      dir = Directory(await databaseFactory.getDatabasesPath());
      await LocalDb.close();
      await databaseFactory.deleteDatabase(p.join(dir.path, LocalDb.dbName));
      await LocalDb.instance;
      SharedPreferences.setMockInitialValues(const {});
    });
    tearDown(() async {
      await LocalDb.close();
      await databaseFactory.deleteDatabase(p.join(dir.path, LocalDb.dbName));
    });

    test('sign-in trades the code for tokens, then an import stores the activities', () async {
      final store = _Mem();
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.url.path == '/oauth/token') {
          expect(req.bodyFields['code'], 'abc');
          return http.Response(
              jsonEncode({
                'access_token': 'A1',
                'refresh_token': 'R1',
                'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              }),
              200);
        }
        expect(req.headers['Authorization'], 'Bearer A1');
        return http.Response(
            jsonEncode([
              {'id': 9, 'start_date': '2026-11-20T07:00:00Z', 'elapsed_time': 1200, 'sport_type': 'Run'},
            ]),
            200);
      });
      late Uri opened;
      final acct = StravaAccount(
        store: store,
        client: client,
        // The link carries whatever state the page was opened with.
        links: Stream.fromFuture(Future(() => _cb(opened.queryParameters['state']!))),
        open: (u) async {
          opened = u;
          return true;
        },
      );
      await acct.saveCredentials('123', 'shh');
      expect(await acct.signIn(), isNull);
      expect(await acct.connected(), isTrue);
      final r = await acct.sync();
      expect(r.error, isNull);
      expect(r.workouts, 1);
      expect((await LocalDb.importedWorkouts()).single['source'], 'Strava');
      expect(calls, ['POST /oauth/token', 'GET /api/v3/athlete/activities']);
    });

    test('an expired token is refreshed before the read', () async {
      final store = _Mem()
        ..m.addAll({
          'strava_client_id': '123',
          'strava_client_secret': 'shh',
          'strava_access': 'OLD',
          'strava_refresh': 'R1',
          'strava_expires': '1',
        });
      final seen = <String>[];
      final client = MockClient((req) async {
        if (req.url.path == '/oauth/token') {
          expect(req.bodyFields['grant_type'], 'refresh_token');
          return http.Response(
              jsonEncode({
                'access_token': 'NEW',
                'refresh_token': 'R2',
                'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              }),
              200);
        }
        seen.add(req.headers['Authorization']!);
        return http.Response('[]', 200);
      });
      final r = await StravaAccount(store: store, client: client).sync();
      expect(r.error, isNull);
      expect(seen, ['Bearer NEW']);
      expect(store.m['strava_refresh'], 'R2');
    });

    test('refused tokens and rate limits come back as a sentence, not a throw', () async {
      final store = _Mem()
        ..m.addAll({
          'strava_refresh': 'R1',
          'strava_access': 'A',
          'strava_expires': '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}',
        });
      final limited = StravaAccount(
          store: store, client: MockClient((_) async => http.Response('', 429)));
      expect((await limited.sync()).error, contains('limiting'));
      final gone = StravaAccount(
          store: store, client: MockClient((_) async => http.Response('', 401)));
      expect((await gone.sync()).error, contains('again'));
    });
  });
}
