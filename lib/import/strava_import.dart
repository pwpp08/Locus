// Bring a Strava account's activities in.
//
// Signing in is Strava's own OAuth page, opened in the browser (or the Strava
// app); it hands a one-time code back to this app on a deep link, and the code
// is exchanged for tokens here. Tokens live in secure storage and never leave
// the device except to Strava.
//
// WHAT COMES IN: a list of activities, as `imported_workout` rows labelled
// "Strava", with the same standing as a workout imported from a health store
// (see health_workout_import.dart): shown in History with the source named,
// counted toward the week, never an input to strain, load or a record, and never
// summed with ours. Strava's calories and distances are Strava's numbers.
//
// WHICH CLIENT. Strava ties a sign-in to an API application's client id and
// secret, and there is no flow without the secret. A build can bake one in
// (`--dart-define=STRAVA_CLIENT_ID=… --dart-define=STRAVA_CLIENT_SECRET=…`);
// without one the person registers their own at strava.com/settings/api (a
// minute, free) and pastes the two values in. The secret is kept in secure
// storage and is the only credential this file ever stores besides the tokens.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../data/db.dart';
import '../health/health_import_state.dart';
import '../health/health_workout_import.dart'
    show ImportedWorkoutRow, deletedUuids;

const String kStravaBuildId = String.fromEnvironment('STRAVA_CLIENT_ID');
const String kStravaBuildSecret = String.fromEnvironment('STRAVA_CLIENT_SECRET');

/// Where Strava hands the code back. The scheme is the app's own; the host is
/// not `login-callback`, which belongs to the community sign-in.
const String kStravaRedirect = 'wtf.openstrap.locus://strava-callback';
const String kStravaHost = 'strava-callback';

/// How far back an import reaches, matching the health-store import.
const int kStravaWindowDays = 90;

/// What the person has to grant: reading their activities.
const String kStravaScope = 'activity:read';

/// Small storage seam, so the account is tested without a keystore.
abstract interface class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore();
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// The sign-in page for [clientId], as Strava's mobile endpoint (it opens the
/// Strava app when installed, the web page otherwise).
Uri stravaAuthorizeUrl(String clientId, String state) =>
    Uri.https('www.strava.com', '/oauth/mobile/authorize', {
      'client_id': clientId,
      'redirect_uri': kStravaRedirect,
      'response_type': 'code',
      'approval_prompt': 'auto',
      'scope': kStravaScope,
      'state': state,
    });

/// What a callback link carried.
typedef StravaCallback = ({String? code, String? error});

/// The code in a callback link, or the reason there is none. Null when the link
/// is not ours or its state is not the one this sign-in made (a stale or forged
/// link must not complete a sign-in).
StravaCallback? parseStravaCallback(Uri uri, String state) {
  if (uri.host != kStravaHost) return null;
  if (uri.queryParameters['state'] != state) return null;
  final err = uri.queryParameters['error'];
  if (err != null) return (code: null, error: 'Strava said: $err');
  final code = uri.queryParameters['code'];
  if (code == null || code.isEmpty) return (code: null, error: 'No code came back.');
  // The person can untick the activity permission on Strava's page.
  final scope = uri.queryParameters['scope'] ?? '';
  if (!scope.split(',').contains(kStravaScope)) {
    return (
      code: null,
      error: 'Allow Locus to view your activities, then try again.'
    );
  }
  return (code: code, error: null);
}

/// "Run" → "RUN", "TrailRun" → "TRAIL_RUN": the shape a health store's
/// activity names have, so one title function reads both.
String stravaKind(String sport) => sport
    .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => '_')
    .toUpperCase();

/// Rows from a page of Strava's activity list. Pure. A row with no id, no start
/// or an impossible span is dropped, never repaired; distance and energy are
/// kept only when Strava gave a figure above zero. Energy is left out: the list carries
/// kilojoules of work, which is not calories burned.
@visibleForTesting
List<ImportedWorkoutRow> stravaRowsFrom(Object? json) {
  if (json is! List) return const [];
  final out = <ImportedWorkoutRow>[];
  for (final a in json) {
    if (a is! Map) continue;
    final id = a['id'];
    final start = DateTime.tryParse('${a['start_date'] ?? ''}');
    final secs = (a['elapsed_time'] as num?)?.toInt();
    if (id == null || start == null || secs == null) continue;
    if (secs <= 0 || secs > 24 * 3600) continue;
    final s = start.millisecondsSinceEpoch ~/ 1000;
    final sport = '${a['sport_type'] ?? a['type'] ?? ''}'.trim();
    final dist = (a['distance'] as num?)?.toDouble();
    out.add(ImportedWorkoutRow(
      uuid: 'strava:$id',
      startTs: s,
      endTs: s + secs,
      kind: sport.isEmpty ? 'WORKOUT' : stravaKind(sport),
      source: 'Strava',
      distanceM: dist != null && dist > 0 ? dist : null,
    ));
  }
  return out;
}

/// What one Strava import did.
@immutable
class StravaResult {
  const StravaResult({this.workouts = 0, this.error});
  final int workouts;

  /// Why nothing came in, in a sentence for the person; null on success.
  final String? error;
}

class StravaAccount {
  StravaAccount({
    TokenStore? store,
    http.Client? client,
    Stream<Uri>? links,
    Future<bool> Function(Uri)? open,
    DateTime Function()? now,
  })  : _store = store ?? const SecureTokenStore(),
        _http = client ?? http.Client(),
        _links = links,
        _open = open ??
            ((u) => launchUrl(u, mode: LaunchMode.externalApplication)),
        _now = now ?? DateTime.now;

  final TokenStore _store;
  final http.Client _http;
  final Stream<Uri>? _links;
  final Future<bool> Function(Uri) _open;
  final DateTime Function() _now;

  static const _kId = 'strava_client_id';
  static const _kSecret = 'strava_client_secret';
  static const _kAccess = 'strava_access';
  static const _kRefresh = 'strava_refresh';
  static const _kExpires = 'strava_expires';

  /// The client in use: the build's, else the one the person pasted.
  Future<({String id, String secret})?> credentials() async {
    if (kStravaBuildId.isNotEmpty && kStravaBuildSecret.isNotEmpty) {
      return (id: kStravaBuildId, secret: kStravaBuildSecret);
    }
    final id = await _store.read(_kId), secret = await _store.read(_kSecret);
    if (id == null || secret == null || id.isEmpty || secret.isEmpty) return null;
    return (id: id, secret: secret);
  }

  bool get bakedIn => kStravaBuildId.isNotEmpty && kStravaBuildSecret.isNotEmpty;

  Future<void> saveCredentials(String id, String secret) async {
    await _store.write(_kId, id.trim());
    await _store.write(_kSecret, secret.trim());
  }

  Future<bool> connected() async =>
      (await _store.read(_kRefresh))?.isNotEmpty ?? false;

  /// Opens Strava's sign-in and waits for the code to come back, then trades it
  /// for tokens. Returns null on success, else a sentence for the person.
  Future<String?> signIn({Duration wait = const Duration(minutes: 5)}) async {
    final cred = await credentials();
    if (cred == null) return 'Add your Strava client id and secret first.';
    final state = _state();
    final stream = _links ?? AppLinks().uriLinkStream;
    // Listen before leaving the app: the link can arrive the moment we are
    // backgrounded.
    final cb = stream
        .map((u) => parseStravaCallback(u, state))
        .where((c) => c != null)
        .first
        .timeout(wait);
    try {
      if (!await _open(stravaAuthorizeUrl(cred.id, state))) {
        return 'Could not open Strava.';
      }
      final got = (await cb)!;
      if (got.code == null) return got.error;
      return await _tokens({
        'client_id': cred.id,
        'client_secret': cred.secret,
        'code': got.code!,
        'grant_type': 'authorization_code',
      });
    } on TimeoutException {
      return 'Strava did not answer in time.';
    } catch (e) {
      debugPrint('[strava] sign-in: $e');
      return 'Sign-in did not finish.';
    }
  }

  Future<void> signOut() async {
    final token = await _store.read(_kAccess);
    if (token != null) {
      try {
        await _http.post(Uri.https('www.strava.com', '/oauth/deauthorize'),
            headers: {'Authorization': 'Bearer $token'});
      } catch (_) {/* local sign-out is what matters */}
    }
    for (final k in [_kAccess, _kRefresh, _kExpires]) {
      await _store.delete(k);
    }
  }

  /// Posts to the token endpoint and stores what comes back. Null on success.
  Future<String?> _tokens(Map<String, String> body) async {
    final r = await _http.post(Uri.https('www.strava.com', '/oauth/token'),
        body: body);
    if (r.statusCode != 200) {
      return r.statusCode == 400 || r.statusCode == 401
          ? 'Strava refused the sign-in. Check the client id and secret.'
          : 'Strava answered ${r.statusCode}.';
    }
    final j = jsonDecode(r.body) as Map;
    final access = j['access_token'], refresh = j['refresh_token'];
    final exp = (j['expires_at'] as num?)?.toInt();
    if (access is! String || refresh is! String || exp == null) {
      return 'Strava sent an answer this app cannot read.';
    }
    await _store.write(_kAccess, access);
    await _store.write(_kRefresh, refresh);
    await _store.write(_kExpires, '$exp');
    return null;
  }

  /// A valid access token, refreshed when it has under a minute left; null when
  /// not signed in or the refresh was refused.
  Future<String?> _token() async {
    final refresh = await _store.read(_kRefresh);
    if (refresh == null || refresh.isEmpty) return null;
    final exp = int.tryParse(await _store.read(_kExpires) ?? '') ?? 0;
    if (exp - _now().millisecondsSinceEpoch ~/ 1000 > 60) {
      return _store.read(_kAccess);
    }
    final cred = await credentials();
    if (cred == null) return null;
    final err = await _tokens({
      'client_id': cred.id,
      'client_secret': cred.secret,
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
    });
    return err == null ? _store.read(_kAccess) : null;
  }

  /// Reads the window's activities, newest first, and stores them. Never
  /// throws; [StravaResult.error] says what stopped it.
  Future<StravaResult> sync() async {
    try {
      final token = await _token();
      if (token == null) {
        return const StravaResult(error: 'Sign in to Strava again.');
      }
      final after = _now()
              .subtract(const Duration(days: kStravaWindowDays))
              .millisecondsSinceEpoch ~/
          1000;
      final rows = <ImportedWorkoutRow>[];
      for (var page = 1; page <= 10; page++) {
        final r = await _http.get(
            Uri.https('www.strava.com', '/api/v3/athlete/activities', {
              'after': '$after',
              'per_page': '100',
              'page': '$page',
            }),
            headers: {'Authorization': 'Bearer $token'});
        if (r.statusCode == 429) {
          return const StravaResult(
              error: 'Strava is limiting requests. Try again in 15 minutes.');
        }
        if (r.statusCode == 401) {
          return const StravaResult(error: 'Sign in to Strava again.');
        }
        if (r.statusCode != 200) {
          return StravaResult(error: 'Strava answered ${r.statusCode}.');
        }
        final list = jsonDecode(r.body);
        final got = stravaRowsFrom(list);
        rows.addAll(got);
        if (list is! List || list.length < 100) break;
      }
      // A workout the person deleted here stays deleted.
      final dead = await deletedUuids();
      final keep = [
        for (final r in rows)
          if (!dead.contains(r.uuid)) r,
      ];
      await LocalDb.putImportedWorkouts([for (final r in keep) r.toRow()]);
      if (keep.isNotEmpty) await markImported(HealthImport.strava);
      return StravaResult(workouts: keep.length);
    } catch (e) {
      debugPrint('[strava] sync: $e');
      return const StravaResult(error: 'Could not reach Strava.');
    }
  }

  static String _state() {
    final r = Random.secure();
    return [for (var i = 0; i < 8; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')]
        .join();
  }
}
