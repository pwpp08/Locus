// update_service.dart — finding, downloading and installing a newer Locus.
//
// Where updates come from: the project's GitHub releases. Every push to main
// replaces a rolling pre-release called `latest` (see .github/workflows/
// apk.yml), and a tagged release is cut for a version. Both carry the APK as a
// plain file, not a zip.
//
// How a build knows it is out of date. The version number only moves when
// someone bumps it, so CI gives every build its own build number, its commit
// count on main (which only ever grows, and which tagged releases share), and
// names the APK after the
// version, that build and the commit (`locus-0.11.4.87-c07d50f.apk`). A
// release is an update when its build number is higher than the installed
// one. A release named the older way (`locus-0.11.4-c07d50f.apk`) is an
// update when its commit is not the installed one and it was published after
// this build was made ([kBuildSha], [kBuildTime]); with no stamp at all (a
// local build) the version number is compared.
//
// When it looks. On launch and whenever the app comes back to the
// foreground, at most every [UpdateService._recheckAfterSec]. A release the
// user already answered "Later" to is not offered again by itself; the More
// tab still says an update is ready.
//
// How it installs. The APK is downloaded inside the app (checked against the
// SHA-256 GitHub publishes for the file), then Android's installer is opened;
// the phone asks for the usual confirmation. Android allows an update only over
// a build signed with the same key, which the CI keeps the same.
//
// How it tidies up. The downloaded file is deleted the next time the app
// starts, which is, after a successful install, the first thing the new build
// does.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/prefs.dart';
import '../ui2/components/update_dialog.dart';

/// The commit this build was made from, and when (UTC, ISO 8601). Set by the
/// workflows with --dart-define; empty in a local build.
const String kBuildSha = String.fromEnvironment('GIT_SHA');
const String kBuildTime = String.fromEnvironment('BUILD_TIME');

class ReleaseInfo {
  final String tagName;
  final String title;
  final String body;
  final DateTime? publishedAt;
  final String htmlUrl;
  final String? apkUrl;
  final String? apkName;
  final int? apkSize;

  /// The file's SHA-256 as GitHub reports it (hex, no prefix), if it does.
  final String? apkSha256;

  const ReleaseInfo({
    required this.tagName,
    required this.title,
    required this.body,
    this.publishedAt,
    required this.htmlUrl,
    this.apkUrl,
    this.apkName,
    this.apkSize,
    this.apkSha256,
  });

  String get versionClean =>
      tagName.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.trim();

  /// `locus-0.11.4.87-c07d50f.apk` → 0.11.4, build 87 and c07d50f; the older
  /// `locus-0.11.4-c07d50f.apk` has no build.
  static final _name =
      RegExp(r'^locus-(\d+\.\d+\.\d+)(?:\.(\d+))?-([0-9a-f]{7,40})\.apk$');
  String? get apkVersion => _name.firstMatch(apkName ?? '')?.group(1);

  /// The CI build number, when the file's name carries one.
  int? get build => int.tryParse(_name.firstMatch(apkName ?? '')?.group(2) ?? '');

  /// The commit the file was built from, when its name says.
  String? get sha => _name.firstMatch(apkName ?? '')?.group(3);

  /// The version a person reads: `v0.11.4 · build 87`, or the commit for a
  /// file named the older way, or the tag.
  String get label {
    final v = apkVersion ?? versionClean;
    if (build != null) return 'v$v · build $build';
    return sha == null ? 'v$v' : 'v$v · $sha';
  }

  /// What changed, as the release notes say it: the commit message, without
  /// the boilerplate older rolling releases wrapped it in or a co-author line.
  String get whatsNew {
    var s = body.trim();
    s = s.replaceFirst(RegExp(r'^Built from [0-9a-f]{7,40}:\s*'), '');
    s = s.replaceFirst(RegExp(r'\s*Replaced on every push to main\.?\s*$'), '');
    return s
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('Co-Authored-By:'))
        .join('\n')
        .trim();
  }

  String get formattedSize {
    if (apkSize == null || apkSize! <= 0) return '';
    final mb = apkSize! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    String? apkUrl, apkName, apkSha;
    int? apkSize;
    final assets = json['assets'] as List?;
    if (assets != null) {
      for (final a in assets) {
        if (a is Map) {
          final name = (a['name'] as String? ?? '');
          if (name.toLowerCase().endsWith('.apk')) {
            apkUrl = a['browser_download_url'] as String?;
            apkName = name;
            apkSize = (a['size'] as num?)?.toInt();
            final digest = a['digest'] as String?;
            if (digest != null && digest.startsWith('sha256:')) {
              apkSha = digest.substring(7);
            }
            break;
          }
        }
      }
    }
    return ReleaseInfo(
      tagName: json['tag_name'] as String? ?? '',
      title: json['name'] as String? ??
          json['tag_name'] as String? ??
          'New release',
      body: json['body'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      htmlUrl: json['html_url'] as String? ??
          'https://github.com/pwpp08/Locus/releases',
      apkUrl: apkUrl,
      apkName: apkName,
      apkSize: apkSize,
      apkSha256: apkSha,
    );
  }
}

class UpdateCheckResult {
  final bool hasUpdate;
  final String currentVersion;
  final ReleaseInfo? latestRelease;
  final String? error;

  const UpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    this.latestRelease,
    this.error,
  });
}

/// One step of an in-app update, for the dialog to draw.
class UpdateProgress {
  /// `downloading`, `installing` or `error`.
  final String phase;
  final int percent;
  final String? message;
  const UpdateProgress(this.phase, {this.percent = 0, this.message});
}

class UpdateService extends ChangeNotifier {
  static const String repoOwner = 'pwpp08';
  static const String repoName = 'Locus';

  /// The one preference behind the "check automatically" switch. The service
  /// and the Settings row both read it, through [Prefs].
  static const String autoCheckKey = 'auto_check_updates';
  static const String _kLastCheck = 'locus_last_update_check_ts';

  /// The release last offered automatically and answered "Later": not
  /// offered again by itself.
  static const String _kDeclined = 'locus_update_declined';

  /// How soon an automatic check may repeat: coming back to the app more
  /// often than this reuses the last answer.
  static const int _recheckAfterSec = 15 * 60;

  static final UpdateService instance = UpdateService._();
  UpdateService._();

  ReleaseInfo? _latestRelease;
  bool _hasUpdate = false;
  bool _checking = false;
  bool _downloading = false;
  String? _lastError;
  String _currentVersion = '';

  /// This build's build number (its commit count on CI, or the pubspec's for
  /// a local build).
  int? _currentBuildNumber;

  ReleaseInfo? get latestRelease => _latestRelease;
  bool get hasUpdate => _hasUpdate;
  bool get isChecking => _checking;
  String? get lastError => _lastError;
  String get currentVersion => _currentVersion;

  /// What is installed, as a person reads it: `v0.11.4 · build 87`.
  String get currentBuild => _currentVersion.isEmpty
      ? ''
      : _currentBuildNumber == null
          ? 'v$_currentVersion'
          : 'v$_currentVersion · build $_currentBuildNumber';

  /// Whether [remote] is strictly newer than [current] (0.11.3 vs 0.11.4).
  static bool isNewerVersion(String current, String remote) {
    final cParts = _parseSemver(current);
    final rParts = _parseSemver(remote);
    for (var i = 0; i < 3; i++) {
      final c = i < cParts.length ? cParts[i] : 0;
      final r = i < rParts.length ? rParts[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }
    return false;
  }

  static List<int> _parseSemver(String v) {
    final clean = v.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.trim();
    return [
      for (final s in clean.split('.'))
        int.tryParse(RegExp(r'^\d+').firstMatch(s)?.group(0) ?? '') ?? 0,
    ];
  }

  /// The newest release that carries an APK, from GitHub's list (newest
  /// first). The `/releases/latest` endpoint is not used: it never returns a
  /// pre-release, and the rolling `latest` build is one.
  static ReleaseInfo? pickRelease(List<dynamic> releases) {
    for (final r in releases) {
      if (r is! Map || r['draft'] == true) continue;
      final info = ReleaseInfo.fromJson(r.cast<String, dynamic>());
      if (info.apkUrl != null) return info;
    }
    return null;
  }

  /// Whether [r] is newer than this build. See the file header.
  static bool isUpdate(
    ReleaseInfo r, {
    required String version,
    int? build,
    String sha = kBuildSha,
    String builtAt = kBuildTime,
  }) {
    final theirBuild = r.build;
    if (theirBuild != null && build != null) return theirBuild > build;
    final theirs = r.sha;
    if (theirs != null && sha.isNotEmpty) {
      // The same commit, however either is abbreviated.
      if (theirs.startsWith(sha) || sha.startsWith(theirs)) return false;
      final built = DateTime.tryParse(builtAt);
      final published = r.publishedAt;
      // Published before the installed build was made: older, not newer.
      if (built != null && published != null && !published.isAfter(built)) {
        return false;
      }
      return true;
    }
    return isNewerVersion(version, r.apkVersion ?? r.versionClean);
  }

  bool get autoCheckEnabled => Prefs.getBool(autoCheckKey, true);

  Future<void> setAutoCheckEnabled(bool enabled) async {
    Prefs.setBool(autoCheckKey, enabled);
    notifyListeners();
  }

  Future<UpdateCheckResult> checkForUpdates({
    bool force = false,
    http.Client? client,
  }) async {
    UpdateCheckResult now() => UpdateCheckResult(
          hasUpdate: _hasUpdate,
          currentVersion: _currentVersion,
          latestRelease: _latestRelease,
        );
    if (_checking) return now();

    _checking = true;
    _lastError = null;
    notifyListeners();

    final c = client ?? http.Client();
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      _currentBuildNumber = int.tryParse(info.buildNumber);

      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (!force &&
          _latestRelease != null &&
          nowSec - Prefs.getInt(_kLastCheck, 0) < _recheckAfterSec) {
        return now();
      }
      Prefs.setInt(_kLastCheck, nowSec);

      final resp = await c.get(
        Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/'
            'releases?per_page=10'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Locus-App',
        },
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        throw Exception('GitHub answered ${resp.statusCode}');
      }
      final release = pickRelease(jsonDecode(resp.body) as List<dynamic>);
      _latestRelease = release;
      _hasUpdate = release != null &&
          isUpdate(release,
              version: _currentVersion, build: _currentBuildNumber);
      return now();
    } catch (e) {
      _lastError = '$e';
      return UpdateCheckResult(
        hasUpdate: _hasUpdate,
        currentVersion: _currentVersion,
        latestRelease: _latestRelease,
        error: '$e',
      );
    } finally {
      _checking = false;
      notifyListeners();
      if (client == null) c.close();
    }
  }

  /// Downloads [r]'s APK and opens Android's installer for it. Errors arrive
  /// as an `error` [UpdateProgress]; the dialog offers the browser then.
  Stream<UpdateProgress> install(ReleaseInfo r) async* {
    final url = r.apkUrl;
    if (!Platform.isAndroid || url == null) {
      yield const UpdateProgress('error',
          message: 'This build cannot install updates itself.');
      return;
    }
    if (_downloading) {
      yield const UpdateProgress('error',
          message: 'A download is already running.');
      return;
    }
    _downloading = true;
    try {
      await for (final e in OtaUpdate().execute(
        url,
        destinationFilename: 'locus-update.apk',
        sha256checksum: r.apkSha256,
      )) {
        switch (e.status) {
          case OtaStatus.DOWNLOADING:
            yield UpdateProgress('downloading',
                percent: int.tryParse(e.value ?? '') ?? 0);
          case OtaStatus.INSTALLING:
          case OtaStatus.INSTALLATION_DONE:
            yield const UpdateProgress('installing', percent: 100);
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            yield const UpdateProgress('error',
                message: 'Allow Locus to install apps in Android’s '
                    'settings, then try again.');
          case OtaStatus.CHECKSUM_ERROR:
            yield const UpdateProgress('error',
                message: 'The download did not match what was published, so '
                    'it was not installed.');
          case OtaStatus.CANCELED:
            yield const UpdateProgress('error', message: 'Cancelled.');
          default:
            yield UpdateProgress('error',
                message: 'The update could not be installed'
                    '${e.value == null ? '' : ' (${e.value})'}.');
        }
      }
    } catch (e) {
      yield UpdateProgress('error', message: 'The update failed: $e');
    } finally {
      _downloading = false;
    }
  }

  /// The downloaded APK, once an update has been installed. Called when the app
  /// starts: after an install the new build starts here, and what is left on
  /// disk is a ~40 MB file nobody needs. Never deletes while one is downloading.
  Future<void> cleanupInstalled() async {
    if (!Platform.isAndroid || _downloading) return;
    try {
      final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/ota_update');
      if (!await dir.exists()) return;
      await for (final f in dir.list()) {
        if (f is File && f.path.toLowerCase().endsWith('.apk')) {
          await f.delete();
        }
      }
    } catch (e) {
      debugPrint('[updater] cleanup failed: $e');
    }
  }

  /// Open the release in the browser, to download and install by hand (also the
  /// way out when Android refuses an install).
  static Future<bool> startDownload(ReleaseInfo release) async {
    try {
      return await launchUrl(
        Uri.parse(release.apkUrl ?? release.htmlUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('[updater] could not open the download: $e');
      return false;
    }
  }

  /// The key a release is remembered by when it is declined.
  static String _keyOf(ReleaseInfo r) => r.apkName ?? r.tagName;

  /// "Later" on a release offered by itself: it is not offered again.
  void decline(ReleaseInfo r) => Prefs.setString(_kDeclined, _keyOf(r));

  Future<void> check(BuildContext context, {bool manual = false}) async {
    final res = await checkForUpdates(force: manual);
    if (!context.mounted) return;
    final r = res.latestRelease;
    if (res.hasUpdate && r != null) {
      if (!manual && Prefs.getString(_kDeclined, '') == _keyOf(r)) return;
      await UpdateDialog.show(context, release: r);
    } else if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.error != null
                ? 'Could not check for updates. Try again later.'
                : 'Locus is up to date ($currentBuild)',
          ),
        ),
      );
    }
  }

  /// On launch and on every return to the foreground. Throttled by
  /// [checkForUpdates]; never while a sheet from an earlier check is open.
  Future<void> checkOnStartup(BuildContext context) async {
    if (!autoCheckEnabled || !context.mounted || _offering) return;
    _offering = true;
    try {
      await check(context, manual: false);
    } finally {
      _offering = false;
    }
  }

  bool _offering = false;
}
