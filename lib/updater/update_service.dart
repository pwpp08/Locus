// update_service.dart — checks for and downloads new GitHub releases for Locus.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui2/components/update_dialog.dart';

class ReleaseInfo {
  final String tagName;
  final String title;
  final String body;
  final DateTime? publishedAt;
  final String htmlUrl;
  final String? apkUrl;
  final int? apkSize;

  const ReleaseInfo({
    required this.tagName,
    required this.title,
    required this.body,
    this.publishedAt,
    required this.htmlUrl,
    this.apkUrl,
    this.apkSize,
  });

  String get versionClean =>
      tagName.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.trim();

  String get formattedSize {
    if (apkSize == null || apkSize! <= 0) return '';
    final mb = apkSize! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    String? apkUrl;
    int? apkSize;
    final assets = json['assets'] as List?;
    if (assets != null) {
      for (final a in assets) {
        if (a is Map) {
          final name = (a['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = a['browser_download_url'] as String?;
            apkSize = (a['size'] as num?)?.toInt();
            break;
          }
        }
      }
    }

    DateTime? pub;
    final pubStr = json['published_at'] as String?;
    if (pubStr != null) {
      pub = DateTime.tryParse(pubStr);
    }

    return ReleaseInfo(
      tagName: json['tag_name'] as String? ?? '',
      title: json['name'] as String? ?? json['tag_name'] as String? ?? 'New Release',
      body: json['body'] as String? ?? '',
      publishedAt: pub,
      htmlUrl: json['html_url'] as String? ?? 'https://github.com/pwpp08/Locus/releases',
      apkUrl: apkUrl,
      apkSize: apkSize,
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

class UpdateService extends ChangeNotifier {
  static const String repoOwner = 'pwpp08';
  static const String repoName = 'Locus';
  static const String _kAutoCheck = 'locus_auto_check_updates';
  static const String _kLastCheck = 'locus_last_update_check_ts';

  static final UpdateService instance = UpdateService._();
  UpdateService._();

  ReleaseInfo? _latestRelease;
  bool _hasUpdate = false;
  bool _checking = false;
  String? _lastError;
  String _currentVersion = '';

  ReleaseInfo? get latestRelease => _latestRelease;
  bool get hasUpdate => _hasUpdate;
  bool get isChecking => _checking;
  String? get lastError => _lastError;
  String get currentVersion => _currentVersion;

  /// Compares two semver strings (e.g. 0.11.3 vs 0.11.4).
  /// Returns true if [remote] is strictly newer than [current].
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
    final segments = clean.split('.');
    final result = <int>[];
    for (final s in segments) {
      final digits = RegExp(r'^\d+').firstMatch(s)?.group(0);
      result.add(digits != null ? int.tryParse(digits) ?? 0 : 0);
    }
    return result;
  }

  Future<bool> isAutoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoCheck) ?? true;
  }

  Future<void> setAutoCheckEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoCheck, enabled);
    notifyListeners();
  }

  Future<UpdateCheckResult> checkForUpdates({
    bool force = false,
    http.Client? client,
  }) async {
    if (_checking) {
      return UpdateCheckResult(
        hasUpdate: _hasUpdate,
        currentVersion: _currentVersion,
        latestRelease: _latestRelease,
      );
    }

    _checking = true;
    _lastError = null;
    notifyListeners();

    final c = client ?? http.Client();
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;

      final prefs = await SharedPreferences.getInstance();
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (!force) {
        final lastCheck = prefs.getInt(_kLastCheck) ?? 0;
        // Throttle automatic background checks to once every 4 hours
        if (nowSec - lastCheck < 14400 && _latestRelease != null) {
          _checking = false;
          notifyListeners();
          return UpdateCheckResult(
            hasUpdate: _hasUpdate,
            currentVersion: _currentVersion,
            latestRelease: _latestRelease,
          );
        }
      }

      await prefs.setInt(_kLastCheck, nowSec);

      final uri = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );
      final resp = await c.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Locus-App',
        },
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final release = ReleaseInfo.fromJson(json);
        _latestRelease = release;

        final remoteVer = release.versionClean;
        _hasUpdate = isNewerVersion(_currentVersion, remoteVer);
        _checking = false;
        notifyListeners();

        return UpdateCheckResult(
          hasUpdate: _hasUpdate,
          currentVersion: _currentVersion,
          latestRelease: release,
        );
      } else if (resp.statusCode == 404) {
        _hasUpdate = false;
        _latestRelease = null;
        _checking = false;
        notifyListeners();
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: _currentVersion,
        );
      } else {
        throw Exception('GitHub API returned status ${resp.statusCode}');
      }
    } catch (e) {
      _lastError = '$e';
      _checking = false;
      notifyListeners();
      return UpdateCheckResult(
        hasUpdate: _hasUpdate,
        currentVersion: _currentVersion,
        latestRelease: _latestRelease,
        error: '$e',
      );
    } finally {
      if (client == null) c.close();
    }
  }

  /// Launch APK download in system browser/downloader or open release page.
  static Future<bool> startDownload(ReleaseInfo release) async {
    final targetUrl = release.apkUrl ?? release.htmlUrl;
    final uri = Uri.parse(targetUrl);
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('[updater] Failed to launch download URL: $e');
      return false;
    }
  }

  Future<void> check(BuildContext context, {bool manual = false}) async {
    final res = await checkForUpdates(force: manual);
    if (!context.mounted) return;
    if (res.hasUpdate && res.latestRelease != null) {
      UpdateDialog.show(
        context,
        release: res.latestRelease!,
        currentVersion: res.currentVersion,
      );
    } else if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.error != null
                ? 'Check failed: ${res.error}'
                : 'Locus is up to date (v${res.currentVersion})',
          ),
        ),
      );
    }
  }

  Future<void> checkOnStartup(BuildContext context) async {
    final auto = await isAutoCheckEnabled();
    if (!auto || !context.mounted) return;
    await check(context, manual: false);
  }
}
