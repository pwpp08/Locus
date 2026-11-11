// The updater: it has to find a rolling pre-release, tell whether it is newer
// than the installed build even though both are "0.11.4", and offer to install
// it. These pin the parts that used to fail silently: GitHub's /releases/latest
// never returns a pre-release, and a version number alone cannot order two
// builds of one version.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/components/update_dialog.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:openstrap_edge/updater/update_service.dart';

import 'support/fonts.dart';

Map<String, Object?> _release({
  String tag = 'latest',
  String? apk = 'locus-0.11.4-c07d50f.apk',
  bool draft = false,
  String published = '2026-10-31T16:00:00Z',
  String? digest,
  String body = 'Built from c07d50f: fix things.',
}) =>
    {
      'tag_name': tag,
      'name': 'Latest build',
      'body': body,
      'draft': draft,
      'published_at': published,
      'html_url': 'https://github.com/pwpp08/Locus/releases/tag/$tag',
      'assets': [
        if (apk != null)
          {
            'name': apk,
            'size': 41 * 1024 * 1024,
            'browser_download_url':
                'https://github.com/pwpp08/Locus/releases/download/$tag/$apk',
            'digest': ?digest,
          },
      ],
    };

void main() {
  setUpAll(loadAppFonts);

  group('reading a release', () {
    test('the apk, its commit, its version and its checksum', () {
      final r = ReleaseInfo.fromJson(_release(digest: 'sha256:abc123'));
      expect(r.apkName, 'locus-0.11.4-c07d50f.apk');
      expect(r.sha, 'c07d50f');
      expect(r.apkVersion, '0.11.4');
      expect(r.apkSha256, 'abc123',
          reason: 'no "sha256:" prefix for the plugin');
      expect(r.label, 'v0.11.4 · c07d50f');
      expect(r.formattedSize, '41.0 MB');
    });

    test('a CI build carries its build number, and that is its name', () {
      final r = ReleaseInfo.fromJson(_release(apk: 'locus-0.11.4.87-c07d50f.apk'));
      expect(r.apkVersion, '0.11.4');
      expect(r.build, 87);
      expect(r.sha, 'c07d50f');
      expect(r.label, 'v0.11.4 · build 87');
    });

    test('what is new is the commit message, without the old boilerplate', () {
      expect(
          ReleaseInfo.fromJson(_release(
                  body: 'Built from c07d50f: Fix sync. Replaced on every push '
                      'to main.'))
              .whatsNew,
          'Fix sync.');
      expect(
          ReleaseInfo.fromJson(_release(
                  body: 'Fix sync\n\n- the bar hides\n\nCo-Authored-By: X <x@y>'))
              .whatsNew,
          'Fix sync\n\n- the bar hides');
    });

    test('a tagged release has no commit in its name; the tag is the version',
        () {
      final r = ReleaseInfo.fromJson(
          _release(tag: 'v0.12.0', apk: 'openstrap-edge-v0.12.0.apk'));
      expect(r.sha, isNull);
      expect(r.versionClean, '0.12.0');
      expect(r.label, 'v0.12.0');
    });

    test('the newest release with an apk is the one picked', () {
      final picked = UpdateService.pickRelease([
        _release(tag: 'draft', draft: true),
        _release(tag: 'notes-only', apk: null),
        _release(tag: 'latest'),
        _release(tag: 'v0.1.0', apk: 'old.apk'),
      ]);
      expect(picked?.tagName, 'latest');
    });

    test('nothing with an apk picks nothing', () {
      expect(UpdateService.pickRelease([_release(apk: null)]), isNull);
      expect(UpdateService.pickRelease(const []), isNull);
    });
  });

  group('is it newer than what is installed', () {
    final rolling = ReleaseInfo.fromJson(_release());
    bool newer(
            {String sha = '', String built = '', String version = '0.11.4'}) =>
        UpdateService.isUpdate(rolling,
            version: version, sha: sha, builtAt: built);

    test('the same commit is not an update, however it is abbreviated', () {
      expect(newer(sha: 'c07d50f'), isFalse);
      expect(newer(sha: 'c07d50f9e8a7b6c5'), isFalse);
    });

    test('another commit published after this build was made is', () {
      expect(newer(sha: '18949887', built: '2026-10-30T10:00:00Z'), isTrue);
    });

    test('another commit published BEFORE this build was made is not', () {
      expect(newer(sha: '18949887', built: '2026-11-02T10:00:00Z'), isFalse,
          reason: 'a local or newer build must not be offered the older one');
    });

    test('with no stamp on this build the version number decides', () {
      expect(newer(version: '0.11.3'), isTrue);
      expect(newer(version: '0.11.4'), isFalse);
      expect(newer(version: '0.12.0'), isFalse);
    });

    test('between two numbered builds the build number decides', () {
      final b87 =
          ReleaseInfo.fromJson(_release(apk: 'locus-0.11.4.87-c07d50f.apk'));
      expect(UpdateService.isUpdate(b87, version: '0.11.4', build: 85), isTrue);
      expect(UpdateService.isUpdate(b87, version: '0.11.4', build: 87), isFalse);
      expect(UpdateService.isUpdate(b87, version: '0.11.4', build: 90), isFalse);
    });

    test('semantic versions compare numerically, not as text', () {
      expect(UpdateService.isNewerVersion('0.9.0', '0.10.0'), isTrue);
      expect(UpdateService.isNewerVersion('0.10.0', '0.9.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.0', '1.0.0'), isFalse);
    });
  });

  group('checking GitHub', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
      PackageInfo.setMockInitialValues(
        appName: 'Locus',
        packageName: 'wtf.openstrap.openstrap_edge',
        version: '0.11.3',
        buildNumber: '1',
        buildSignature: '',
      );
    });

    http.Client answering(int status, Object body, {List<Uri>? seen}) =>
        MockClient((req) async {
          seen?.add(req.url);
          return http.Response(jsonEncode(body), status);
        });

    test('finds the rolling pre-release through the list, not /latest',
        () async {
      final seen = <Uri>[];
      final res = await UpdateService.instance.checkForUpdates(
          force: true, client: answering(200, [_release()], seen: seen));
      expect(res.hasUpdate, isTrue);
      expect(res.latestRelease?.tagName, 'latest');
      expect(seen.single.path, endsWith('/releases'),
          reason: '/releases/latest would 404 on a pre-release');
    });

    test('an empty list is "up to date", not an error', () async {
      final res = await UpdateService.instance
          .checkForUpdates(force: true, client: answering(200, const []));
      expect(res.hasUpdate, isFalse);
      expect(res.error, isNull);
    });

    test('a failing GitHub is an error the screen can say, never a crash',
        () async {
      final res = await UpdateService.instance
          .checkForUpdates(force: true, client: answering(403, {'m': 'rate'}));
      expect(res.error, isNotNull);
      expect(UpdateService.instance.lastError, isNotNull);
    });

    test('the automatic-check switch is the key the service reads', () async {
      final svc = UpdateService.instance;
      await svc.setAutoCheckEnabled(false);
      expect(Prefs.getBool(UpdateService.autoCheckKey, true), isFalse);
      expect(svc.autoCheckEnabled, isFalse);
      await svc.setAutoCheckEnabled(true);
      expect(svc.autoCheckEnabled, isTrue);
    });
  });

  group('the update sheet', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
    });

    Future<void> open(WidgetTester t, ReleaseInfo r) async {
      t.view.physicalSize = const Size(390 * 3, 900 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => UpdateDialog.show(c, release: r),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('says what is available and offers to install it here',
        (t) async {
      await open(t, ReleaseInfo.fromJson(_release()));
      expect(find.text('UPDATE AVAILABLE'), findsOneWidget);
      expect(find.text('v0.11.4 · c07d50f'), findsWidgets);
      expect(find.text('UPDATE NOW'), findsOneWidget);
      expect(find.text('fix things.'), findsOneWidget);
      expect(find.text('OPEN IN BROWSER'), findsNothing,
          reason: 'the browser is the way out of a failure, not the first move');
    });

    testWidgets('a release with no apk can only be opened in the browser',
        (t) async {
      await open(t, ReleaseInfo.fromJson(_release(apk: null)));
      expect(find.text('UPDATE NOW'), findsNothing);
      expect(find.text('OPEN IN BROWSER'), findsOneWidget);
    });

    testWidgets('Later closes it', (t) async {
      await open(t, ReleaseInfo.fromJson(_release()));
      await t.tap(find.text('LATER'));
      await t.pumpAndSettle();
      expect(find.text('UPDATE AVAILABLE'), findsNothing);
    });
  });
}
