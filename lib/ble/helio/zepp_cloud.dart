// Fetching a Helio Strap's pairing key from the owner's own Zepp account.
//
// The strap will only talk to a phone that holds the 16-byte key Zepp made when
// the strap was first linked. Zepp keeps that key on its server, in the device
// list of the signed-in account. The owner signs in on Zepp's own page; we read
// the session cookie that page sets, ask the same server for the device list,
// and pick the strap out. The password never reaches Locus, and nothing leaves
// the phone except the owner's own request to Zepp.
//
// Pure Dart on purpose: the WebView and the cookie read live in the sign-in
// screen, so everything here can be tested with a canned response.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'channel.dart' show helioParseAuthKey;

/// The Zepp app identity the device list expects in its query and headers.
const String kZeppAppId = '428135909242707968';
const String kZeppAppName = 'com.huami.midong';
const String kZeppVersionName = '10.10.5-play';
const String kZeppVersionCode = '151997';

/// Where the owner signs in, and the cookie URLs that carry the session.
const String kZeppSignInUrl =
    'https://user.zepp.com/universalLogin/index.html#/login'
    '?project_name=watchface'
    '&project_redirect_uri=https%3A%2F%2Fwatchface.zepp.com%2Fcreate'
    '&platform_app=com.huami.webapp';
const List<String> kZeppCookieUrls = [
  'https://watchface.zepp.com',
  'https://zepp.com',
  'https://user.zepp.com',
  'https://user.huami.com',
];

/// Account regions, tried in order. A token only works on its own region and the
/// others answer 401/403, which is how we move on.
const List<String> kZeppApiHosts = [
  'https://api-mifit.zepp.com/',
  'https://api-mifit-us2.zepp.com/',
  'https://api-mifit-us3.zepp.com/',
  'https://api-mifit-de2.zepp.com/',
  'https://api-mifit-sg2.zepp.com/',
];

final RegExp _mac = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');

/// A signed-in Zepp session: the app token and the account id it belongs to.
class ZeppSession {
  const ZeppSession({required this.userId, required this.appToken});
  final String userId;
  final String appToken;
}

/// One device row from the account, reduced to what pairing needs.
class ZeppDevice {
  const ZeppDevice({
    required this.mac,
    required this.deviceSource,
    required this.productId,
    this.key,
    this.serial,
    this.hardware,
    this.bindingStatus,
    this.activeStatus,
  });

  /// Upper-case, colon-separated.
  final String mac;
  final int deviceSource;
  final int productId;

  /// The 16-byte pairing key, or null when the row carries none that parses.
  final Uint8List? key;
  final String? serial;
  final String? hardware;
  final int? bindingStatus;
  final int? activeStatus;

  /// 10289410 / 10289411 are the two Helio Strap sources, 157 its product id.
  bool get isHelio =>
      deviceSource == 10289410 || deviceSource == 10289411 || productId == 157;
}

/// Reads the session out of the cookie header Android's CookieManager returns.
///
/// Zepp's page keeps it in `hm-user-login-info`, a URL-encoded JSON blob (the
/// encoding is sometimes applied twice). Older pages set plain `apptoken` and
/// `userid` cookies instead. Returns null when neither is there yet, which is
/// the normal state until the owner finishes signing in.
ZeppSession? zeppSessionFromCookies(String? header) {
  if (header == null || header.trim().isEmpty) return null;
  final jar = <String, String>{};
  for (final part in header.split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    jar[part.substring(0, i).trim()] = part.substring(i + 1).trim();
  }

  final blob = jar['hm-user-login-info'];
  if (blob != null) {
    var s = blob;
    // Up to three layers of percent-encoding; stop when it reads as JSON.
    for (var i = 0; i < 3 && !s.trimLeft().startsWith('{'); i++) {
      try {
        final d = Uri.decodeComponent(s);
        if (d == s) break;
        s = d;
      } catch (_) {
        break;
      }
    }
    try {
      final j = jsonDecode(s);
      if (j is Map) {
        final t = j['token_info'];
        final tok = t is Map ? t : j;
        final app = _str(tok['app_token']);
        final uid = _str(tok['user_id']) ?? _str(j['user_id']);
        if (app != null && uid != null) {
          return ZeppSession(userId: uid, appToken: app);
        }
      }
    } catch (_) {/* fall through to the plain cookies */}
  }

  final app = jar['apptoken'];
  final uid = jar['userid'];
  if (app != null && app.isNotEmpty && uid != null && uid.isNotEmpty) {
    return ZeppSession(userId: uid, appToken: app);
  }
  return null;
}

String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

/// Parses a device-list response. Rows with a malformed MAC are dropped (the
/// strap is found by MAC); a key that is not 32 hex digits is kept as null
/// rather than guessed at. Throws [FormatException] when the body is not the
/// expected JSON at all, so a wrong host or a sign-in page is not read as
/// "no devices".
List<ZeppDevice> parseZeppDevices(String body) {
  final Object? j;
  try {
    j = jsonDecode(body);
  } catch (_) {
    throw const FormatException('Zepp did not return JSON');
  }
  final items = j is Map ? j['items'] : null;
  if (items is! List) throw const FormatException('Zepp device list has no items');

  final out = <ZeppDevice>[];
  for (final raw in items) {
    if (raw is! Map) continue;
    final mac = _str(raw['macAddress'])?.toUpperCase();
    if (mac == null || !_mac.hasMatch(mac)) continue;

    // additionalInfo is a JSON string on some accounts and an object on others.
    Map<dynamic, dynamic> info = const {};
    final a = raw['additionalInfo'];
    if (a is Map) {
      info = a;
    } else if (a is String && a.isNotEmpty) {
      try {
        final d = jsonDecode(a);
        if (d is Map) info = d;
      } catch (_) {}
    }

    final k = _str(info['auth_key']) ?? _str(raw['auth_key']);
    out.add(ZeppDevice(
      mac: mac,
      deviceSource: _int(raw['deviceSource']),
      productId: _int(raw['productId'] ?? info['productId']),
      key: k == null ? null : helioParseAuthKey(k),
      serial: _str(info['sn']) ?? _str(raw['sn']),
      hardware: _str(info['hardwareVersion']) ?? _str(raw['hardwareVersion']),
      bindingStatus: raw['bindingStatus'] == null ? null : _int(raw['bindingStatus']),
      activeStatus: raw['activeStatus'] == null ? null : _int(raw['activeStatus']),
    ));
  }
  return out;
}

/// The Helio on the account. With more than one (a replaced strap), the one
/// that has a key wins, then the one still bound, then the one still active.
ZeppDevice? pickHelioStrap(List<ZeppDevice> all) {
  final h = all.where((d) => d.isHelio).toList();
  if (h.isEmpty) return null;
  int rank(ZeppDevice d) =>
      (d.key != null ? 4 : 0) +
      (d.bindingStatus == 1 ? 2 : 0) +
      (d.activeStatus == 1 ? 1 : 0);
  var best = h.first;
  for (final d in h.skip(1)) {
    if (rank(d) > rank(best)) best = d;
  }
  return best;
}

/// Why the lookup did not produce a device list.
enum ZeppFailure { rejected, unreachable, unreadable }

class ZeppCloudException implements Exception {
  ZeppCloudException(this.kind);
  final ZeppFailure kind;
  @override
  String toString() => 'ZeppCloudException($kind)';
}

/// Asks Zepp for the account's devices.
class ZeppCloud {
  ZeppCloud({http.Client? client, this.timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client();
  final http.Client _client;
  final Duration timeout;

  /// Tries each regional host until one accepts the token. A 401/403 means
  /// "not my region" and moves on; if every host says so the session is
  /// [ZeppFailure.rejected]. Any other failure is [ZeppFailure.unreachable] or
  /// [ZeppFailure.unreadable].
  Future<List<ZeppDevice>> listDevices(ZeppSession s,
      {String lang = 'en', String country = 'US', String timezone = 'Etc/UTC'}) async {
    var sawReject = false;
    var sawNetwork = false;
    var sawUnreadable = false;
    for (final host in kZeppApiHosts) {
      final uri = Uri.parse('${host}users/${Uri.encodeComponent(s.userId)}/devices')
          .replace(queryParameters: {
        'enableMultiDeviceOnMultiType': 'true',
        'enableMultiDevice': 'true',
        'userid': s.userId,
        'appid': kZeppAppId,
        'channel': 'play',
        'device': 'android_30',
        'device_type': 'android_phone',
        'cv': '${kZeppVersionCode}_$kZeppVersionName',
        'v': '2.0',
        'lang': lang,
        'country': country,
        'timezone': timezone,
      });
      final http.Response r;
      try {
        r = await _client.get(uri, headers: {
          'apptoken': s.appToken,
          'appname': kZeppAppName,
          'appplatform': 'android_phone',
          'channel': 'play',
          'cv': '${kZeppVersionCode}_$kZeppVersionName',
          'v': '2.0',
          'lang': lang,
          'country': country,
          'timezone': timezone,
          'hm-privacy-diagnostics': 'false',
          'hm-privacy-ceip': 'false',
          'X-Request-Id': DateTime.now().microsecondsSinceEpoch.toRadixString(16),
        }).timeout(timeout);
      } catch (_) {
        sawNetwork = true;
        continue;
      }
      if (r.statusCode == 401 || r.statusCode == 403) {
        sawReject = true;
        continue;
      }
      if (r.statusCode != 200) {
        sawUnreadable = true;
        continue;
      }
      try {
        return parseZeppDevices(utf8.decode(r.bodyBytes));
      } on FormatException {
        // Some regions answer 200 with an error body for a foreign token.
        sawReject = true;
      }
    }
    if (sawReject) throw ZeppCloudException(ZeppFailure.rejected);
    if (sawNetwork) throw ZeppCloudException(ZeppFailure.unreachable);
    if (sawUnreadable) throw ZeppCloudException(ZeppFailure.unreadable);
    throw ZeppCloudException(ZeppFailure.unreachable);
  }

  void close() => _client.close();
}
