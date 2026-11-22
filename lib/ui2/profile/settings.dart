import '../../l10n/display_text.dart';
// Settings, and editing the profile.
//
// Two deliberate departures from the reference design:
//
//   · "Log out" is "Reset all data". Logging out of an app with no server is
//     theatre — it clears a session that does not exist while leaving every
//     byte on disk. The destructive action here is the honest one, and it says
//     what it destroys.
//   · Email, username, bio, location and date of birth are gone from the edit
//     form. None of them feed a metric, and a field that changes nothing is a
//     field that implies an account.

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../compute/profile.dart' show birthDateOf, wholeYearsOn;
import '../../data/day_label.dart';
import '../../health/health_export.dart' show HealthLinkState;
import '../../l10n/app_localizations.dart';
import '../../platform/tasker_bridge.dart';
import '../../notify/notification_prefs.dart';
import '../../notify/notification_service.dart';
import '../../state/ai_button_prefs.dart';
import '../../state/app_state.dart';
import '../../state/clock_format.dart';
import '../../state/prefs.dart';
import '../../state/units_controller.dart';
import '../../telemetry/health_uploader.dart';
import '../ui2.dart';
import '../screens/coach.dart';
import '../screens/weight_trend_screen.dart' show WeightTrendScreen;
import '../../updater/update_service.dart';
import '../community/community.dart' show CommunityScreen;
import '../onboarding/profile_setup.dart'
    show BirthdayPage, BodyPage, NamePage, SexPage, nameFields, namesOf;
import 'band_notifications.dart' show BandNotifications;
import 'data.dart' show DataScreen;
import 'gestures.dart' show BandGestures;
import 'storage_screen.dart' show StorageScreen;
import 'gallery.dart';
import 'profile.dart';
import 'report_issue.dart';
import 'whoop_import_screen.dart';
import 'wearable_numbers.dart' show WearableDisplay, wearableSettingsGroup;

/// Unwind the profile stack back to the gate.
///
/// `_Gate` is `MaterialApp.home` — the BOTTOM of the navigator stack — so an
/// action that changes `AppState.route` swaps what is under everything without
/// popping any of it. Resetting all data, forgetting the band and asking to
/// pair again are all route changes taken from a pushed screen, and all three
/// used to leave the user staring at the screen they tapped from, describing a
/// state that no longer existed.
void backToRoot(BuildContext c) =>
    Navigator.of(c).popUntil((r) => r.isFirst);

// ══════════════════ MORE SETTINGS ══════════════════

/// Taps on the version row that reveal the developer group. The conventional
/// gesture, for the conventional reason: it is discoverable by anyone who
/// already knows it and invisible to everyone else.
const kDevTaps = 7;

class MoreSettings extends StatefulWidget {
  const MoreSettings({super.key});

  @override
  State<MoreSettings> createState() => _MoreSettingsState();
}

class _MoreSettingsState extends State<MoreSettings> {
  bool _dev = Prefs.getBool(Prefs.devMode, false);

  String _version = '';
  int _taps = 0;

  @override
  void initState() {
    super.initState();
    _readVersion();
    // The developer wearable toggles list the paired devices; best-effort.
    if (_dev) {
      WearableDisplay.instance.loadDevices().catchError((Object _) {});
    }
  }

  Future<void> _readVersion() async {
    try {
      final i = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = '${i.version} (${i.buildNumber})');
    } catch (_) {/* no version, no row — and no way in */}
  }

  void _tapVersion() {
    if (_dev || ++_taps < kDevTaps) return;
    _setDev(true);
  }

  /// The one preference here that is awaited. A revocation that never reached
  /// storage is back ON at the next launch, so it does not get to fail quietly
  /// — the switch still moves (in-session it really is off, nothing is sent),
  /// and the person is told it did not stick.

  void _setDev(bool on) {
    Prefs.setBool(Prefs.devMode, on);
    if (on) WearableDisplay.instance.loadDevices().catchError((Object _) {});
    setState(() {
      _dev = on;
      _taps = 0;
    });
  }

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final units = c.watch<UnitsController>();
    final clock = c.watch<ClockFormatController>();
    return MoreSettingsView(
      version: _version,
      devMode: _dev,
      onVersionTap: _tapVersion,
      onToggleDev: () => _setDev(false),
      onGallery: () => goto(c, const GalleryScreen()),
      units: units.system.label,
      clockFormat: clock.format,
      telemetry: app.telemetryConsent,
      // Shown when the build has the feature OR when this install already
      // consented under an older build. A consent that cannot be withdrawn is
      // not consent, and the old `lib/ui` toggle died with that package while
      // the pref — and the daily whole-database upload it authorises — did not.
      showHealthShare: kHealthDataContributionEnabled || app.healthShareConsent,
      healthShare: app.healthShareConsent,
      showUpdateChecks: app.updateChecksAvailable,
      updateChecks: app.updateChecksEnabled,
      updateAvailable: app.updateAvailable,
      updateMandatory: app.updateMandatory,
      onUpdates: () => UpdateService.instance.check(c, manual: true),
      onAutomation: () => goto(c, const AutomationSettings()),
      onUnits: (i) => units.setSystem(UnitSystem.values[i]),
      // the wind-down body bakes the time in when it's armed, re-arm it now
      onClockFormat: (i) async {
        try {
          await clock.setFormat(ClockFormat.values[i]);
        } finally {
          await app.refreshAiReminders();
        }
      },
      onToggleTelemetry: () => app.setTelemetryConsent(!app.telemetryConsent),
      onToggleHealthShare: () => _toggleHealthShare(c, app),
      onToggleUpdateChecks: () =>
          app.setUpdateChecksEnabled(!app.updateChecksEnabled),
      onReset: () => _confirmReset(c, app),
    );
  }
}

/// Turn the Apple Health / Health Connect EXPORT on or off.
///
/// `setHealthSync` already requests the OS permission and kicks a first sync;
/// this row is the only thing that was ever missing. Until it existed the app
/// shipped a write entitlement, a usage string and ten Android WRITE_*
/// permissions for a code path that could not run — see
/// docs/internal/UNREACHABLE.md P1.
///
/// Health Connect has two failure modes that are not refusals and must not be
/// reported as one: it may not be installed, or it may be too old. Both are
/// answered with the action that fixes them rather than an error.
Future<void> _toggleHealthSync(AppState app) async {
  if (app.healthSyncEnabled) {
    await app.setHealthSync(false);
    return;
  }
  await app.setHealthSync(true);
  switch (app.healthState) {
    case HealthLinkState.notInstalled:
    case HealthLinkState.needsUpdate:
      await app.installHealthConnect();
    case HealthLinkState.needsPermission:
      // Android only sends the user to Health Connect's own screen; on iOS
      // there is nothing to open, and `openSettings` is a no-op there.
      await app.openHealthConnect();
    case HealthLinkState.ready:
    case HealthLinkState.unsupported:
    case HealthLinkState.unknown:
      break;
  }
}

/// One line saying what the export is actually doing right now.
String healthSyncSub(
    BuildContext c, bool on, HealthLinkState state, String store) {
  final l = AppLocalizations.of(c);
  if (!on) {
    return l?.settingsHealthSyncOff(store) ?? 'Off. Nothing is written to $store';
  }
  return switch (state) {
    HealthLinkState.ready => l?.settingsHealthSyncReady(store) ??
        'Writes each day’s sleep, resting heart rate, '
            'HRV, respiratory rate, energy and workouts to $store once it is final',
    HealthLinkState.needsPermission =>
      l?.settingsHealthSyncNeedsPermission(store) ??
          '$store has not granted write access. Tap to open it',
    HealthLinkState.notInstalled => l?.settingsHealthSyncNotInstalled ??
        'Health Connect is not installed. Tap to '
            'get it',
    HealthLinkState.needsUpdate => l?.settingsHealthSyncNeedsUpdate ??
        'Health Connect is too old to write to. Tap to update it',
    HealthLinkState.unsupported => l?.settingsHealthSyncUnsupported ??
        'This device has no health store to write to',
    HealthLinkState.unknown =>
      l?.settingsHealthSyncChecking(store) ?? 'Checking $store…',
  };
}

/// Grant or withdraw the whole-database health contribution.
///
/// Asymmetric on purpose. Granting is confirmed first — it authorises a daily
/// upload of the ENTIRE database, raw signal included, which is the largest
/// thing this app can ever send anywhere. Withdrawing takes effect
/// IMMEDIATELY, with no dialog in the way, and only then says what had already
/// been sent: a revocation you have to confirm is a revocation that can be
/// mis-tapped into staying on.
Future<void> _toggleHealthShare(BuildContext c, AppState app) async {
  if (app.healthShareConsent) {
    await app.setHealthShareConsent(false);
    final last = await HealthUploader.instance.lastUploadAt();
    if (!c.mounted) return;
    final l = AppLocalizations.of(c);
    await showDialog<void>(
      context: c,
      builder: (d) => AppDialog(
        title: l?.settingsHealthShareOffTitle ?? 'Contribution off',
        body: last == null
              ? (l?.settingsHealthShareOffNeverUploaded ??
                  'Nothing was ever uploaded. Nothing will be.')
              // What we KNOW, not what we hope: the revocation is posted
              // once, unawaited, with no retry queue, so offline it never
              // arrives and nothing here can tell.
              : (l?.settingsHealthShareOffDetail(
                      last.toLocal().toString().split('.').first) ??
                  'Nothing further will be uploaded.\n\n'
                      'One copy of your database was uploaded on '
                      '${last.toLocal().toString().split('.').first}. The server '
                      'keeps only the most recent copy per device. We tried to '
                      'tell it your consent is withdrawn — that message is sent '
                      'once and is not retried, so if this phone is offline it '
                      'will not have arrived, and we cannot show you that the copy '
                      'is gone either.'),
        actions: [
          BigButton(l?.settingsOk ?? 'OK', onTap: () => Navigator.of(d).pop()),
        ],
      ),
    );
    return;
  }
  final l = AppLocalizations.of(c);
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AppDialog(
      title: l?.settingsHealthShareOnTitle ?? 'Contribute your health data?',
      body: l?.settingsHealthShareOnBody ??
            'Once a day, on Wi-Fi and while charging, a compressed copy of your '
                'ENTIRE database is uploaded — every day of scores and every raw sensor '
                'row the band has sent. It is used to improve the algorithms.\n\n'
                'It is not anonymous in any meaningful sense: it is your whole health '
                'history. You can switch this off at any time, and nothing further '
                'is sent from that moment.',
      actions: [
        BigButton(l?.settingsNo ?? 'No', soft: true, onTap: () => Navigator.of(d).pop(false)),
        BigButton(l?.settingsContribute ?? 'Contribute', onTap: () => Navigator.of(d).pop(true)),
      ],
    ),
  );
  if (ok == true) await app.setHealthShareConsent(true);
}

Future<void> _confirmReset(BuildContext c, AppState app) async {
  final l = AppLocalizations.of(c);
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AppDialog(
      title: l?.settingsResetTitle ?? 'Delete everything?',
      // Enumerated, because the previous wording ("every measured day, session
      // and profile field") was false in about twenty places: it deleted the
      // derived days and left the labs, the meals, the doses, the breathing
      // sessions, the logged sets, the baselines, the consent flags, the
      // install id, the stored API key and the home-screen widget standing.
      // It now removes all of that, so it can say so.
      body: withIosUninstallWarning(c, l?.settingsResetBody ??
            'This permanently deletes this app\'s data on this device:\n\n'
                '· every measured day, sleep, workout and route\n'
                '· every lab result, meal, medication dose, habit, breathing session '
                'and logged set\n'
                '· your journal, cycle log and what the app has learned as your usual\n'
                '· your profile, every preference and any stored AI key\n'
                '· the home-screen widget and every scheduled reminder\n\n'
                'Exported copies and backups in previous or unavailable folders '
                'may remain. Delete those separately.\n\n'
                'The band is unpaired, and it cannot re-send history it has already '
                'handed over. Export from Your data first if you want a copy.'),
      actions: [
        BigButton(l?.settingsResetKeepData ?? 'Keep my data', soft: true, onTap: () => Navigator.of(d).pop(false)),
        BigButton(l?.settingsResetDeleteEverything ?? 'Delete everything', onTap: () => Navigator.of(d).pop(true)),
      ],
    ),
  );
  if (ok != true || !c.mounted) return;
  final messenger = ScaffoldMessenger.of(c);
  String? backupCleanupError;
  try {
    backupCleanupError = await app.resetAllData();
  } catch (e) {
    if (c.mounted) {
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(
        content: Text(l?.dataFailed(e.toString()) ?? 'Failed: $e'),
      ));
    }
    return;
  }
  // resetAllData swaps the gate to Welcome, which is UNDER this screen —
  // without this the user stays on Settings, reading a profile that has been
  // deleted.
  if (c.mounted) backToRoot(c);
  if (backupCleanupError != null && messenger.mounted) {
    messenger.showSnackBar(SnackBar(
      content: Text(l?.settingsResetBackupWarning ??
          'App data deleted. Backup cleanup was incomplete. '
              'Some files or folder access may remain.'),
    ));
  }
}

class MoreSettingsView extends StatelessWidget {
  final String units;

  /// 12- or 24-hour clock, or whatever the OS says ("System", the default).
  final ClockFormat clockFormat;
  final bool telemetry;

  /// The health-contribution row appears only where it means something: a
  /// build that has the feature, or an install that already said yes to it.
  final bool showHealthShare, healthShare;

  /// The legacy release-server check appears only on a build that can check.
  final bool showUpdateChecks, updateChecks;

  /// What the last check ANSWERED. The check itself was already running and
  /// already storing its answer; this row is the only place in the app that
  /// says what it found, so without these two the whole poll was a no-op.
  final bool updateAvailable, updateMandatory;

  /// `0.9.26 (57)`, or empty until package_info answers — the About group is
  /// the whole reveal gesture, so it is not drawn against a blank.
  final String version;

  /// Off by default and off on every fresh install. The group it gates is not
  /// a feature: nothing in it is for anyone who has not deliberately asked.
  final bool devMode;

  final VoidCallback? onVersionTap, onToggleDev, onGallery;

  /// Look for a newer build now; null hides the app-update rows.
  final VoidCallback? onUpdates;

  final VoidCallback? onAutomation,
      onToggleTelemetry,
      onToggleHealthShare,
      onToggleUpdateChecks,
      onReset;

  /// The index of the choice tapped: units (metric, imperial), time format
  /// (system, 24 h, 12 h).
  final ValueChanged<int>? onUnits, onClockFormat;

  const MoreSettingsView({
    super.key,
    this.units = 'Metric',
    this.clockFormat = ClockFormat.system,
    this.telemetry = false,
    this.showHealthShare = false,
    this.healthShare = false,
    this.showUpdateChecks = false,
    this.updateChecks = true,
    this.updateAvailable = false,
    this.updateMandatory = false,
    this.version = '',
    this.devMode = false,
    this.onVersionTap,
    this.onToggleDev,
    this.onGallery,
    this.onUpdates,
    this.onAutomation,
    this.onUnits,
    this.onClockFormat,
    this.onToggleTelemetry,
    this.onToggleHealthShare,
    this.onToggleUpdateChecks,
    this.onReset,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return settingsPage(c, l?.settingsNavTitle ?? 'Settings', [
      // The app itself. You, the band, your zones, notifications and your
      // data each have a page of their own on the More tab; nothing here
      // repeats them.
      //
      // Every group is named for the question it answers, in the order
      // people come looking: how the app reads, updates, what it talks to,
      // the coach's model, privacy, then help. The one destructive action
      // sits alone at the end.
      settingsGroup(c, 'Display', [
        SetDropdown(
            LucideIcons.ruler,
            l?.settingsUnitsRowTitle ?? 'Units',
            const ['Metric', 'Imperial'],
            units == 'Imperial' ? 1 : 0,
            onChanged: onUnits),
        SetDropdown(
            LucideIcons.clock,
            l?.settingsClockFormatRowTitle ?? 'Time format',
            [
              l?.settingsClockFormatSystem ?? ClockFormat.system.label,
              l?.settingsClockFormat24h ?? ClockFormat.h24.label,
              l?.settingsClockFormat12h ?? ClockFormat.h12.label,
            ],
            clockFormat.index,
            onChanged: onClockFormat),
      ]),
      if (onUpdates != null || showUpdateChecks)
        settingsGroup(c, 'Updates', [
          if (onUpdates != null)
            AnimatedBuilder(
              animation: UpdateService.instance,
              builder: (c, _) {
                final u = UpdateService.instance;
                return SetRow(LucideIcons.downloadCloud, C.dialStrain,
                    'App updates',
                    value: u.isChecking
                        ? 'Checking…'
                        : u.hasUpdate
                            ? 'Update ready'
                            : u.currentBuild,
                    onTap: u.isChecking ? null : onUpdates);
              },
            ),
          if (onUpdates != null)
            AnimatedBuilder(
              animation: UpdateService.instance,
              builder: (c, _) {
                final u = UpdateService.instance;
                return SetRow(LucideIcons.refreshCw, C.dialStrain,
                    'Check automatically',
                    sub: 'Looks for a newer build when the app opens',
                    switchValue: u.autoCheckEnabled,
                    onTap: () => u.setAutoCheckEnabled(!u.autoCheckEnabled));
              },
            ),
          if (showUpdateChecks)
            SetRow(LucideIcons.refreshCw, C.dialStrain,
                l?.settingsCheckForUpdatesRowTitle ?? 'Check for updates',
                sub: updateMandatory
                    ? (l?.settingsUpdateBelowMinimum ??
                        'This build is below the minimum supported '
                            'build. Install the newer release from GitHub')
                    : updateAvailable
                        ? (l?.settingsUpdateAvailable ??
                            'A newer build is published on GitHub')
                        : (l?.settingsUpdateCheckSub ??
                            'Asks the release server on launch. It sees '
                                'your IP address and when you open the app'),
                switchValue: updateChecks,
                onTap: onToggleUpdateChecks),
        ]),
      settingsGroup(c, 'Connected apps', [
        SetRow(LucideIcons.workflow, C.dialStrain,
            l?.settingsTaskerShortcutsRowTitle ?? 'Tasker and Shortcuts',
            // The row states the asymmetry rather than leaving it to the
            // screen.
            sub: l?.settingsTaskerShortcutsRowSub ??
                'Android only for events out. iOS can buzz the band '
                    'but cannot be triggered by it',
            onTap: onAutomation),
      ]),
      settingsGroup(c, 'AI provider', [
        SetRow.brand((t) => CoachMark(size: I.lg, color: t), C.dialStrain,
            'Model and key',
            sub: 'The AI coach’s model, its API key and how it answers',
            onTap: () => goto(c, const CoachSetup())),
        SetRow(LucideIcons.messageSquare, C.dialStrain, 'AI button',
            sub: 'The floating button that opens the coach anywhere',
            onTap: () => goto(c, const AiButtonSettings())),
      ]),
      settingsGroup(c, l?.settingsGroupPrivacy ?? 'Privacy', [
        SetRow(LucideIcons.bug, C.dialStrain,
            l?.settingsCrashReportsRowTitle ?? 'Crash reports',
            sub: l?.settingsCrashReportsRowSub ??
                'Nothing is sent until you say so',
            switchValue: telemetry,
            onTap: onToggleTelemetry),
        if (showHealthShare)
          SetRow(LucideIcons.cloudUpload, C.dialStrain,
              l?.settingsContributeHealthDataRowTitle ??
                  'Contribute my health data',
              sub: l?.settingsContributeHealthDataRowSub ??
                  'Uploads your whole database once a day, on '
                      'Wi-Fi and charging, to improve the algorithms',
              switchValue: healthShare,
              onTap: onToggleHealthShare),
      ]),
      settingsGroup(c, 'Help and about', [
        SetRow(LucideIcons.messageSquareWarning, C.dialStrain,
            l?.settingsReportIssueRowTitle ?? 'Report an issue',
            sub: l?.settingsReportIssueRowSub ??
                'Sends what you choose to the maintainers, encrypted',
            onTap: () => goto(c, const ReportIssueScreen())),
        // Where the licences of what this app uses are written out in full.
        SetRow(LucideIcons.scale, C.dialStrain,
            l?.settingsNoticesLicencesRowTitle ?? 'Notices and licences',
            sub: l?.settingsNoticesLicencesRowSub ??
                'Who this app is not, and whose data it uses',
            onTap: () => launchUrl(
                Uri.parse('https://openstrap.github.io/edge/notice.html'),
                mode: LaunchMode.externalApplication)),
        if (version.isNotEmpty)
          SetRow(LucideIcons.info, C.dialStrain,
              l?.settingsVersionRowTitle ?? 'Version',
              value: version, chevron: false, onTap: onVersionTap),
      ]),
      // How a non-WHOOP wearable's numbers are drawn. Developer only while
      // every wearable is (rule R6).
      if (devMode) wearableSettingsGroup(c),
      if (devMode)
        settingsGroup(c, l?.settingsGroupDeveloper ?? 'Developer', [
          SetRow(LucideIcons.layoutGrid, C.dialStrain,
              l?.settingsComponentGalleryRowTitle ?? 'Component gallery',
              sub: l?.settingsComponentGalleryRowSub ??
                  'Every component, at any text scale, in either theme',
              onTap: onGallery),
          SetRow(LucideIcons.code, C.dialStrain,
              l?.settingsDeveloperModeRowTitle ?? 'Developer mode',
              switchValue: true, onTap: onToggleDev),
        ]),
      const SizedBox(height: S.x10),
      Center(
        child: BigButton(l?.settingsResetAllDataRowTitle ?? 'Reset all data',
            icon: LucideIcons.trash2,
            tone: ButtonTone.danger,
            compact: true,
            onTap: onReset),
      ),
      const SizedBox(height: S.x3),
      Text('Deletes everything this app has stored on this phone. It asks first.',
          textAlign: TextAlign.center, style: F.over.copyWith(color: p.ink3)),
    ]);
  }
}

/// The floating AI button: on or off, its size, where it sits and how
/// strongly it shows. Every change is live on the shell behind this page.
class AiButtonSettings extends StatelessWidget {
  const AiButtonSettings({super.key});

  @override
  Widget build(BuildContext c) => ValueListenableBuilder<int>(
        valueListenable: AiButtonPrefs.changed,
        builder: (c, _, _) {
          final on = AiButtonPrefs.on;
          return settingsPage(c, 'AI button', [
            settingsGroup(c, '', [
              SetRow(LucideIcons.messageSquare, C.dialStrain, 'Show the button',
                  sub: on
                      ? 'Tap it to ask the coach; hold it to come back here'
                      : 'The coach is still in Home and Settings',
                  switchValue: on,
                  onTap: () => AiButtonPrefs.setOn(!on)),
            ]),
            if (on)
              settingsGroup(c, 'Look', [
                SetDropdown(LucideIcons.maximize2, 'Size',
                    AiButtonPrefs.sizeLabels, AiButtonPrefs.sizeIndex,
                    onChanged: (i) =>
                        AiButtonPrefs.setIndex(AiButtonPrefs.kSize, i)),
                SetDropdown(LucideIcons.mapPin, 'Position',
                    AiButtonPrefs.spotLabels, AiButtonPrefs.spotIndex,
                    onChanged: (i) =>
                        AiButtonPrefs.setIndex(AiButtonPrefs.kSpot, i)),
                SetDropdown(LucideIcons.sunMoon, 'Visibility',
                    AiButtonPrefs.visibilityLabels,
                    AiButtonPrefs.visibilityIndex,
                    onChanged: (i) =>
                        AiButtonPrefs.setIndex(AiButtonPrefs.kVisibility, i)),
              ]),
          ]);
        },
      );
}

/// A settings page: the bar with its name, then its groups.
Widget settingsPage(BuildContext c, String title, List<Widget> children) =>
    Scaffold(
      backgroundColor: P.of(c).bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(title),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: children,
            ),
          ),
        ]),
      ),
    );

// ══════════════════ MY PROFILE · DEVICE · HEALTH ══════════════════

/// Everything that is your data: what comes in (a WHOOP export), what goes
/// out (the health store, export and backup, the cloud copy) and how much
/// room it takes.
class YourDataSettings extends StatefulWidget {
  const YourDataSettings({super.key});

  @override
  State<YourDataSettings> createState() => _YourDataSettingsState();
}

class _YourDataSettingsState extends State<YourDataSettings> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().dataFileBytes().then((b) {
      if (mounted) setState(() => _bytes = b);
    }).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    return YourDataView(
      storage: _bytes == null ? '' : formatBytes(_bytes!),
      healthStore: app.healthStoreName,
      healthSync: app.healthSyncEnabled,
      healthState: app.healthState,
      onToggleHealthSync: () => _toggleHealthSync(app),
    );
  }
}

class YourDataView extends StatelessWidget {
  /// How much room the data takes ("1.4 GB"); empty until it is read.
  final String storage;

  /// The platform health EXPORT. `healthStore` names it — "Apple Health" or
  /// "Health Connect" — because "your health app" is not something a user can
  /// go and grant a permission in.
  final bool healthSync;
  final HealthLinkState healthState;
  final String healthStore;
  final VoidCallback? onToggleHealthSync;

  const YourDataView({
    super.key,
    this.storage = '',
    this.healthSync = false,
    this.healthState = HealthLinkState.unknown,
    this.healthStore = 'Health Connect',
    this.onToggleHealthSync,
  });

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    return settingsPage(c, l?.profileYourDataGroup ?? 'Your data', [
      settingsGroup(c, 'In and out', [
        SetRow(LucideIcons.upload, C.dialStrain, 'Import WHOOP data',
            sub: 'Your recovery, sleep, strain and workouts from a '
                'WHOOP export',
            onTap: () => goto(c, const WhoopImportScreen())),
        SetRow(LucideIcons.heartPulse, C.dialStrain,
            l?.settingsWriteToHealthStoreRowTitle(healthStore) ??
                'Write to $healthStore',
            sub: healthSyncSub(c, healthSync, healthState, healthStore),
            switchValue: healthSync,
            onTap: onToggleHealthSync),
      ]),
      settingsGroup(c, 'Copies and room', [
        SetRow(LucideIcons.hardDriveDownload, C.dialStrain,
            l?.profileExportRow ?? 'Export and backup',
            onTap: () => goto(c, const DataScreen())),
        // The Locus account: optional, and only for the community. It
        // replaced the old self-hosted backup sign-in here.
        SetRow(LucideIcons.circleUserRound, C.dialStrain, 'Locus account',
            sub: 'Optional: teams, leaderboards and chat',
            onTap: () => goto(c, const CommunityScreen())),
        SetRow(LucideIcons.database, C.dialStrain,
            l?.profileStorage ?? 'Storage',
            value: storage,
            onTap: () => goto(c, const StorageScreen())),
      ]),
    ]);
  }
}

// ══════════════════ NOTIFICATIONS ══════════════════
//
// There are exactly three things this app may put in your notification shade:
// the alarm, the day's aggregated exception, and the weekly lookback when the
// week contained something. The app used to be able to emit around twenty-two
// kinds — hydration slots, step goals, posture nudges, AI briefings — and none
// of them had a switch anywhere in the app, so the only way to stop any of it
// was the OS. A notification the user cannot turn off is a bug, which makes
// this screen part of the fix rather than a nicety on top of it.
//
// The alarm is deliberately not switchable here: its off switch is cancelling
// the alarm, and burying a second one in settings is how an alarm silently
// fails to wake someone.
//
// The water reminder is on this screen and IS a shade entry — a strap buzz and
// a phone notification at the same minute, because a buzz alone needs a live
// link and a live isolate and so is not a reminder. It reminds you to LOG a
// drink — the app measures no hydration and this screen may never imply it
// does. See MT-14 in IDEAS.md.

class NotificationSettings extends StatefulWidget {
  const NotificationSettings({super.key});

  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings> {
  NotificationPrefs? _prefs;
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await NotificationPrefs.load();
    final granted = await NotificationService.instance.hasPermission();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _granted = granted;
    });
  }

  Future<void> _apply(NotificationPrefs next) async {
    setState(() => _prefs = next);
    await next.save();
    // Re-run the scheduler so a switch that was just turned off actually
    // cancels what it was standing for, rather than taking effect at some
    // later resume.
    //
    // Through AppState, not straight at the NotificationCenter: the medication
    // slots need the med schedule and the check-in needs today's journal, and
    // only AppState can read either. Calling the centre directly cancels what
    // the switch turned off and arms nothing back, so meds stayed silent until
    // the next foreground pass.
    if (mounted) await context.read<AppState>().refreshAiReminders();
    // the water buzz is an in-memory timer, not an OS slot — re-arm it here or
    // the switch only takes effect at the next launch.
    if (mounted) await context.read<AppState>().armWaterReminder(next);
    // the low-battery threshold is restored once per process — push the new
    // value into the alert pipeline or it applies only after a restart.
    if (mounted) {
      await context.read<AppState>().refreshBatteryThreshold(next);
    }
  }

  /// The one contextual moment left where prompting is honest: the user is
  /// standing in the notifications screen, having just asked for one.
  Future<void> _requestPermission() async {
    final ok = await NotificationService.instance.ensurePermission();
    if (mounted) setState(() => _granted = ok);
  }

  @override
  Widget build(BuildContext c) {
    final p = _prefs;
    final app = c.watch<AppState>();
    return NotificationSettingsView(
      prefs: p ?? const NotificationPrefs(),
      loaded: p != null,
      granted: _granted,
      onChanged: _apply,
      onRequestPermission: _requestPermission,
      zoneAlert: app.zoneAlertEnabled,
      zoneAlertTarget: app.zoneAlertTargetZone,
      onZoneAlert: () => app.setZoneAlertEnabled(!app.zoneAlertEnabled),
      onZoneAlertTarget: app.setZoneAlertTargetZone,
    );
  }
}

class NotificationSettingsView extends StatelessWidget {
  final NotificationPrefs prefs;
  final bool loaded, granted;

  final Future<void> Function(NotificationPrefs next)? onChanged;
  final VoidCallback? onRequestPermission;

  /// The band's buzz when a live workout crosses into or out of the target
  /// zone (1–5). Off by default: an existing user did not ask their band to
  /// start buzzing mid-workout.
  final bool zoneAlert;
  final int zoneAlertTarget;
  final VoidCallback? onZoneAlert;
  final ValueChanged<int>? onZoneAlertTarget;

  const NotificationSettingsView({
    super.key,
    this.prefs = const NotificationPrefs(),
    this.loaded = true,
    this.granted = true,
    this.onChanged,
    this.onRequestPermission,
    this.zoneAlert = false,
    this.zoneAlertTarget = 3,
    this.onZoneAlert,
    this.onZoneAlertTarget,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    void set(NotificationPrefs next) => onChanged?.call(next);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(l?.settingsNotificationsNavTitle ?? 'Notifications',
                sub: l?.settingsNotificationsNavSub ??
                    'WHAT MAY INTERRUPT YOU'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                if (!granted)
                  StatusCard(
                    l?.settingsNotificationsOffSystemTitle ??
                        'Notifications are off at the system level',
                    l?.settingsNotificationsOffSystemBody ??
                        'Nothing below can reach you until the OS lets it.',
                    fix: l?.settingsTurnThemOn ?? 'Turn them on',
                    icon: LucideIcons.bellOff,
                    onFix: onRequestPermission,
                  ),
                if (loaded) ...[
                  // What the band itself does, here as well as under the
                  // device: a buzz is a notification too.
                  settingsGroup(c, 'On the band', [
                    if (defaultTargetPlatform == TargetPlatform.android)
                      SetRow(LucideIcons.vibrate, C.dialStrain, 'Band buzzes',
                          sub: 'Which phone notifications the band buzzes for',
                          onTap: () => goto(c, const BandNotifications())),
                    SetRow(LucideIcons.hand, C.stressLow, 'Double-tap',
                        sub: 'What a double-tap on the band does',
                        onTap: () => goto(c, const BandGestures())),
                  ]),
                  settingsGroup(c, 'Health', [
                    SetRow(LucideIcons.heartPulse, C.dialStrain,
                        l?.settingsHealthExceptionsRowTitle ??
                            'Health exceptions',
                        sub: l?.settingsHealthExceptionsRowSub ??
                            'One a day at most, and only when something moved away from your usual',
                        switchValue: prefs.healthEnabled,
                        onTap: () => set(prefs.copyWith(
                            healthEnabled: !prefs.healthEnabled))),
                    // The retained recovery-channel switch, now with a real
                    // event behind it again: the morning "recovery is ready"
                    // note. It was cut in the three-class cull and sat dead —
                    // emitted, classified null, dropped.
                    SetRow(LucideIcons.activity, C.optimal,
                        l?.settingsRecoveryReadyRowTitle ?? 'Recovery ready',
                        sub: l?.settingsRecoveryReadyRowSub ??
                            'One note when your morning recovery score '
                                'lands',
                        switchValue: prefs.recoveryEnabled,
                        onTap: () => set(prefs.copyWith(
                            recoveryEnabled: !prefs.recoveryEnabled))),
                    // Says what it DOES now: the finding is computed from the
                    // week's own crossday rollup (medical flags first, then a
                    // plainly-stated resting-HR drift), and most weeks still
                    // say nothing — which is the point.
                    SetRow(LucideIcons.calendarDays, C.dialStrain,
                        l?.settingsWeeklyLookbackRowTitle ??
                            'Weekly lookback',
                        sub: l?.settingsWeeklyLookbackRowSub ??
                            'Sunday evening, but only for a week that '
                                'actually found something. Most weeks are quiet',
                        switchValue: prefs.remindersEnabled,
                        onTap: () => set(prefs.copyWith(
                            remindersEnabled: !prefs.remindersEnabled))),
                  ]),
                  settingsGroup(c, 'Band and alarm', [
                    SetRow(LucideIcons.watch, C.strainDown,
                        l?.settingsBandAlertsRowTitle ?? 'Band alerts',
                        sub: l?.settingsBandAlertsRowSub ??
                            'Flat battery, on the charger, gone quiet',
                        switchValue: prefs.deviceEnabled,
                        onTap: () => set(prefs.copyWith(
                            deviceEnabled: !prefs.deviceEnabled))),
                    // The low-battery threshold, only while band alerts are
                    // on — an interval for a muted alert is furniture, same
                    // rule as the water row below.
                    if (prefs.deviceEnabled)
                      SetRow(LucideIcons.batteryLow, C.strainDown,
                          l?.settingsAlertMeAtRowTitle ?? 'Alert me at',
                          sub: l?.settingsAlertMeAtRowSub ??
                              'Warn when the band drops under this charge '
                                  'level',
                          value: '${prefs.batteryAlertPct}%',
                          chevron: false,
                          onTap: () => set(prefs.copyWith(
                              batteryAlertPct:
                                  _nextBatteryPct(prefs.batteryAlertPct)))),
                    // On by default, unlike the reminders below: this exists to
                    // catch a wake alarm that silently isn't going to fire, and
                    // starting silent would defeat the point.
                    SetRow(LucideIcons.alarmClock, C.dialStrain,
                        l?.settingsAlarmLatchFailedRowTitle ??
                            'Alarm not confirmed',
                        sub: l?.settingsAlarmLatchFailedRowSub ??
                            'Warn when the band never confirms an alarm this '
                                'app just armed',
                        switchValue: prefs.alarmLatchFailedEnabled,
                        onTap: () => set(prefs.copyWith(
                            alarmLatchFailedEnabled:
                                !prefs.alarmLatchFailedEnabled))),
                    // Also on by default, same reasoning: silent whenever an
                    // alarm IS armed for tonight, so it only ever speaks up
                    // about a real gap.
                    SetRow(LucideIcons.moon, C.dialStrain,
                        l?.settingsAlarmNightCheckRowTitle ??
                            'No-alarm check-in',
                        sub: l?.settingsAlarmNightCheckRowSub ??
                            'A 7pm heads-up on any night with no wake alarm '
                                'armed — silent otherwise',
                        switchValue: prefs.alarmNightCheckEnabled,
                        onTap: () => set(prefs.copyWith(
                            alarmNightCheckEnabled:
                                !prefs.alarmNightCheckEnabled))),
                  ]),
                  settingsGroup(c, 'Activity', [
                    SetRow(LucideIcons.radar, C.optimal,
                        l?.settingsDetectedWorkoutsRowTitle ?? 'Detected workouts',
                        sub: l?.activityPushHint ?? 'Push alerts only. Suggestions remain in Detected activities.',
                        switchValue: prefs.autoDetectEnabled,
                        onTap: () => set(prefs.copyWith(autoDetectEnabled: !prefs.autoDetectEnabled))),
                    SetRow(LucideIcons.moon, C.dialStrain,
                        l?.activityNapAlerts ?? 'Detected naps',
                        sub: l?.activityPushHint ?? 'Push alerts only. Suggestions remain in Detected activities.',
                        switchValue: prefs.napDetectEnabled,
                        onTap: () => set(prefs.copyWith(napDetectEnabled: !prefs.napDetectEnabled))),
                    SetRow(LucideIcons.heartPulse, C.dialStrain,
                        l?.settingsZoneAlertRowTitle ?? 'HR zone alert',
                        sub: l?.settingsZoneAlertRowSub ??
                            'Buzz when your heart rate crosses into or out of '
                                'the target zone during a live workout',
                        switchValue: zoneAlert,
                        onTap: onZoneAlert),
                    // The target only while the alert is on.
                    if (zoneAlert)
                      SetDropdown(
                          LucideIcons.target,
                          l?.settingsZoneAlertTargetRowTitle ?? 'Target zone',
                          const ['Zone 1', 'Zone 2', 'Zone 3', 'Zone 4', 'Zone 5'],
                          (zoneAlertTarget - 1).clamp(0, 4),
                          onChanged: onZoneAlertTarget == null
                              ? null
                              : (i) => onZoneAlertTarget!(i + 1)),
                    // Off by default, and it is the switch that lets the nudge
                    // be scheduled at all — see
                    // NotificationService.schedulableIds. It had none, so it
                    // was refused there and had never once fired. Covers BOTH
                    // sedentary surfaces: the OS-scheduled two-hour-still
                    // one-shot, and the foreground desk-posture check (which
                    // also buzzes the band when it fires).
                    SetRow(LucideIcons.footprints, C.strainDown,
                        l?.settingsMovementNudgeRowTitle ?? 'Movement nudge',
                        sub: l?.settingsMovementNudgeRowSub ??
                            'After two hours without moving, or 90 minutes at a desk. A phone notification plus a buzz on the band when it’s connected',
                        switchValue: prefs.movementEnabled,
                        onTap: () => set(prefs.copyWith(
                            movementEnabled: !prefs.movementEnabled))),
                    // The step-goal achievement's off switch. On by default:
                    // once a day at most, and only on a real crossing.
                    SetRow(LucideIcons.trophy, C.strainDown,
                        l?.settingsStepGoalAlertsRowTitle ??
                            'Step goal alerts',
                        sub: l?.settingsStepGoalAlertsRowSub ??
                            'Tells you once when today crosses your steps '
                                'goal',
                        switchValue: prefs.stepGoalEnabled,
                        onTap: () => set(prefs.copyWith(
                            stepGoalEnabled: !prefs.stepGoalEnabled))),
                  ]),
                  settingsGroup(c, 'Reminders', [
                    // The wind-down nudge. Silent until the Sleep Coach has
                    // actually LEARNED a bedtime — the nudge's whole content
                    // is that time, so there is no honest fallback.
                    SetRow(LucideIcons.moonStar, C.dialSleep,
                        l?.settingsWindDownRowTitle ?? 'Wind-down',
                        sub: l?.settingsWindDownRowSub ??
                            'A heads-up about 45 minutes before the bedtime '
                                'learned from your own nights, kept clear of your '
                                'quiet hours. Appears after about a week of wear',
                        switchValue: prefs.windDownEnabled,
                        onTap: () => set(prefs.copyWith(
                            windDownEnabled: !prefs.windDownEnabled))),
                    // The one prompt whose time is not a guess: it is the
                    // schedule already typed into the Medication tab. Only a
                    // dose still due is armed, and the notification names no
                    // drug — it lands on a lock screen in front of whoever is
                    // in the room.
                    SetRow(LucideIcons.pill, C.dialStrain,
                        l?.settingsMedicationRemindersRowTitle ??
                            'Medication reminders',
                        sub: l?.settingsMedicationRemindersRowSub ??
                            'One notification per scheduled dose, plus a buzz on the band when it’s connected. Skipped for doses already marked',
                        switchValue: prefs.medsEnabled,
                        onTap: () =>
                            set(prefs.copyWith(medsEnabled: !prefs.medsEnabled))),
                    // ONE prompt for the whole journal, not one per field —
                    // mood, energy, stress and the rest are all the same
                    // screen, so five rows would be five interruptions for one
                    // minute of typing.
                    SetRow(LucideIcons.notebookPen, C.dialStrain,
                        l?.settingsDailyCheckInRowTitle ?? 'Daily check-in',
                        sub: l?.settingsDailyCheckInRowSub ??
                            'One prompt in the evening to write the day — '
                                'mood, energy, stress. Skipped once the day '
                                'already has a rating in it',
                        switchValue: prefs.checkInEnabled,
                        onTap: () => set(prefs.copyWith(
                            checkInEnabled: !prefs.checkInEnabled))),
                    // A prompt to log, not a reading. The app measures no
                    // hydration and this row may never imply it does.
                    SetRow(LucideIcons.glassWater, C.stressLow,
                        l?.settingsWaterReminderRowTitle ?? 'Water reminder',
                        sub: l?.settingsWaterReminderRowSub ??
                            'A buzz on the strap and a notification on your '
                                'phone through your waking hours, to remind you to '
                                'log a drink. Nothing is measured either way',
                        switchValue: prefs.waterEnabled,
                        onTap: () => set(
                            prefs.copyWith(waterEnabled: !prefs.waterEnabled))),
                    // only while it's on — the group is dense enough, and an
                    // interval for a reminder nobody armed is furniture.
                    if (prefs.waterEnabled)
                      SetRow(LucideIcons.timer, C.stressLow,
                          l?.settingsRemindMeEveryRowTitle ??
                              'Remind me every',
                          value: _everyLabel(prefs.waterIntervalMin),
                          chevron: false,
                          onTap: () => set(prefs.copyWith(
                              waterIntervalMin:
                                  _nextEvery(prefs.waterIntervalMin)))),
                  ]),
                  settingsGroup(c, l?.settingsGroupQuietHours ?? 'Quiet hours', [
                    SetRow(LucideIcons.moon, C.dialSleep,
                        l?.settingsQuietHoursRowTitle ?? 'Quiet hours',
                        sub: l?.settingsQuietHoursRowSub ??
                            'Nothing buzzes inside this window',
                        switchValue: prefs.quietEnabled,
                        onTap: () => set(
                            prefs.copyWith(quietEnabled: !prefs.quietEnabled))),
                        SetRow(
                          LucideIcons.sunset,
                          C.dialStrain,
                          l?.settingsQuietHoursStartsRowTitle ?? 'Starts',
                          value: _hhmm(prefs.quietStartMin),
                          chevron: false,
                          onTap: () async {
                            final v = await _pickMinute(c, prefs.quietStartMin);
                            if (v != null) {
                              set(prefs.copyWith(quietStartMin: v));
                            }
                          },
                        ),
                    SetRow(LucideIcons.sunrise, C.recYellow,
                        l?.settingsQuietHoursEndsRowTitle ?? 'Ends',
                        value: _hhmm(prefs.quietEndMin),
                        chevron: false,
                        onTap: () async {
                          final v = await _pickMinute(c, prefs.quietEndMin);
                          if (v != null) set(prefs.copyWith(quietEndMin: v));
                        }),
                    SetRow(LucideIcons.triangleAlert, C.dialStrain,
                        l?.settingsHealthExceptionsBreakThroughRowTitle ??
                            'Health exceptions break through',
                        switchValue: prefs.criticalOverridesQuiet,
                        onTap: () => set(prefs.copyWith(
                            criticalOverridesQuiet:
                                !prefs.criticalOverridesQuiet))),
                  ]),
                ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The water intervals on offer, all inside
  /// [NotificationPrefs.waterIntervalMinAllowed]..[NotificationPrefs.waterIntervalMaxAllowed].
  /// None of them is "recommended" — we have no basis for one.
  static const waterEvery = [
    (30, '30m'),
    (60, '1h'),
    (90, '90m'),
    (120, '2h'),
    (180, '3h'),
    (240, '4h'),
  ];

  static String _everyLabel(int min) =>
      waterEvery.firstWhere((e) => e.$1 == min, orElse: () => (min, '${min}m'))
          .$2;

  /// Tapped through in place, like Units and Appearance. An unknown stored
  /// value (an older build, a hand-edited pref) lands on the first choice.
  static int _nextEvery(int min) {
    final i = waterEvery.indexWhere((e) => e.$1 == min);
    return waterEvery[(i + 1) % waterEvery.length].$1;
  }

  /// Low-battery alert thresholds, tapped through in place like [waterEvery].
  /// Bounds match NotificationPrefs.batteryPctMin/Max, so every choice here is
  /// one the pref will store unclamped.
  static const batteryChoices = [10, 15, 20, 25, 30, 40];

  static int _nextBatteryPct(int pct) {
    final i = batteryChoices.indexOf(pct);
    return batteryChoices[(i + 1) % batteryChoices.length];
  }

  static String _hhmm(int minuteOfDay) => formatClockMinute(minuteOfDay);

  static Future<int?> _pickMinute(BuildContext c, int current) async {
    final picked = await pickTime(
      c,
      initial: TimeOfDay(hour: (current ~/ 60) % 24, minute: current % 60),
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }
}

// ══════════════════ EDIT PROFILE ══════════════════

class EditProfile extends StatelessWidget {
  const EditProfile({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.read<AppState>();
    return EditProfileView(
      initial: app.user ?? const {},
      // The app SHOWED lb and EDITED kg: Health converted on the way out, this
      // form did not convert on the way in, so typing back the 172 lb the app
      // had just printed stored 172 kg.
      units: c.watch<UnitsController>(),
      onSave: (fields) async {
        // A field the user CLEARED must be removed, not merged over — the
        // profile map is a merge, so writing only what is present would keep
        // a stale value alive and score the day against a body that is no
        // longer described.
        await app.updateProfile({
          for (final k in const [
            'name',
            'first_name',
            'last_name',
            'username',
            'sex',
            'age',
            'birth_date',
            'height_cm',
            'weight_kg',
          ])
            k: fields[k],
        });
        if (c.mounted) Navigator.of(c).maybePop();
      },
    );
  }
}

class EditProfileView extends StatefulWidget {
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic> fields) onSave;

  /// Display units for the height and weight fields. Null is metric, which is
  /// also what the storage is — the conversion only exists for imperial.
  final UnitsController? units;

  const EditProfileView(
      {super.key,
      required this.onSave,
      this.initial = const {},
      this.units});

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  late final UnitsController _u =
      widget.units ?? UnitsController.seed(UnitSystem.metric);
  late var _names = nameFields(namesOf(widget.initial).first,
      namesOf(widget.initial).last, namesOf(widget.initial).user);
  late final _age =
      TextEditingController(text: _s(widget.initial['age']));
  late DateTime? _birth = birthDateOf(widget.initial);
  late final _height =
      TextEditingController(text: _u.heightField(widget.initial['height_cm'] as num?));
  late final _weight =
      TextEditingController(text: _u.weightField(widget.initial['weight_kg'] as num?));
  late String? _sex = (widget.initial['sex'] as String?)?.toLowerCase();


  static String _s(Object? v) => v == null ? '' : '$v';

  @override
  void dispose() {
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// A field that cannot be read is NOT a cleared field.
  ///
  /// Every key here is written unconditionally, precisely so a cleared one is
  /// removed rather than merged over — which meant a typo ("78 kg", "78,5")
  /// parsed to null and wiped the stored weight while the screen popped as if
  /// it had saved. Blank still clears; a typo now stops the save and says so.
  void _save() {
    final l = AppLocalizations.of(context);
    final age = Typed.of(_age.text);
    final height = Typed.of(_height.text);
    final weight = Typed.of(_weight.text);
    final birth = _birth;
    final bad = [
      if (birth == null && age.bad) (l?.settingsAgeFieldLabel ?? 'Age'),
      if (height.bad) uiText(context, _u.heightLabel),
      if (weight.bad) uiText(context, _u.weightLabel),
    ];
    if (bad.isNotEmpty) {
      sayUnreadable(context, bad);
      return;
    }
    widget.onSave({
      ..._names,
      'sex': _sex,
      // The birth date decides the age when there is one.
      'age': birth == null
          ? age.value?.round()
          : wholeYearsOn(birth, DateTime.now()),
      'birth_date': birth == null ? null : dayLabelOf(birth),
      // Typed in the units on the label, stored in metric.
      'height_cm': height.value == null ? null : _u.heightToCm(_height.text),
      'weight_kg': weight.value == null ? null : _u.weightToKg(_weight.text),
    });
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _sexWord(AppLocalizations? l) => switch (_sex) {
        'm' => l?.settingsSexMale ?? 'Male',
        'f' => l?.settingsSexFemale ?? 'Female',
        'other' => 'Other',
        _ => '',
      };

  String _birthWord() {
    final b = _birth;
    if (b == null) return '';
    final years = wholeYearsOn(b, DateTime.now());
    return '${b.day} ${_months[b.month - 1]} ${b.year} · $years';
  }

  /// One value, typed in a sheet: the field, and Done.
  Future<void> _editText(String title, TextEditingController ctl,
      TextInputType kind, {String? unit}) async {
    final draft = TextEditingController(text: ctl.text);
    final ok = await AppSheet.show<bool>(
      context,
      title: title,
      child: Row(children: [
          Expanded(
            child: AppField(
              controller: draft,
              keyboardType: kind,
              autofocus: true,
              textStyle: F.head,
              hint: AppLocalizations.of(context)?.settingsNotSetHint ?? 'Not set',
            ),
          ),
          if (unit != null) ...[
            const SizedBox(width: S.x3),
            Text(unit, style: F.body.copyWith(color: P.of(context).ink2)),
          ],
        ]),
      actions: [
        Builder(
          builder: (s) => BigButton('Done',
              onTap: () => Navigator.of(s).pop(true)),
        ),
      ],
    );
    if (ok == true && mounted) setState(() => ctl.text = draft.text.trim());
    draft.dispose();
  }

  /// The profile as this form holds it, for a setup page to start from.
  Map<String, dynamic> get _current => {
        ..._names,
        'sex': _sex,
        if (_birth case final b?) 'birth_date': dayLabelOf(b),
        'height_cm': _u.heightToCm(_height.text),
        'weight_kg': _u.weightToKg(_weight.text),
      };

  /// Opens one of setup's pages with SAVE; its answer comes back here and is
  /// written with the rest when the form is saved.
  Future<Map<String, dynamic>?> _page(
          Widget Function(ValueChanged<Map<String, dynamic>> done,
                  VoidCallback back)
              build) =>
      Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
          builder: (r) => build((f) => Navigator.of(r).pop(f),
              () => Navigator.of(r).pop())));

  Future<void> _editName() async {
    final f = await _page((done, back) => NamePage(
        initial: _current,
        editing: true,
        action: 'SAVE',
        progress: 1,
        onBack: back,
        onDone: done));
    if (f != null && mounted) setState(() => _names = f);
  }

  Future<void> _editSex() async {
    final f = await _page((done, back) => SexPage(
        initial: _current,
        action: 'SAVE',
        progress: 1,
        onBack: back,
        onDone: done));
    if (f != null && mounted) setState(() => _sex = f['sex'] as String?);
  }

  Future<void> _editBirthday() async {
    final f = await _page((done, back) => BirthdayPage(
        initial: _current,
        action: 'SAVE',
        progress: 1,
        onBack: back,
        onDone: done));
    if (f != null && mounted) {
      setState(() => _birth = DateTime.parse(f['birth_date'] as String));
    }
  }

  Future<void> _editBody() async {
    final f = await _page((done, back) => BodyPage(
        initial: _current,
        units: _u,
        action: 'SAVE',
        progress: 1,
        onBack: back,
        onDone: done));
    if (f != null && mounted) {
      setState(() {
        _height.text = _u.heightField(f['height_cm'] as num?);
        _weight.text = _u.weightField(f['weight_kg'] as num?);
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    String unitOf(String label) {
      final m = RegExp(r'\(([^)]+)\)').firstMatch(label);
      return m == null ? '' : m.group(1)!;
    }

    final hUnit = unitOf(_u.heightLabel);
    final wUnit = unitOf(_u.weightLabel);
    String withUnit(String v, String unit) =>
        v.isEmpty ? '' : (unit.isEmpty ? v : '$v $unit');
    final rows = <Widget>[
      _Line('Name',
          value: (_names['name'] as String?) ?? '', onTap: _editName),
      _Line('Username',
          value: (_names['username'] as String?) ?? '', onTap: _editName),
      _Line('Sex',
          value: _sexWord(l), onTap: _editSex),
      _Line('Birthday', value: _birthWord(), onTap: _editBirthday),
      if (_birth == null)
        _Line('Age',
            value: _age.text.trim(),
            onTap: () =>
                _editText('Age', _age, TextInputType.number, unit: 'years')),
      _Line('Height',
          value: withUnit(_height.text.trim(), hUnit), onTap: _editBody),
      _Line('Weight',
          value: withUnit(_weight.text.trim(), wUnit), onTap: _editBody),
    ];
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(l?.settingsEditProfileNavTitle ?? 'Edit profile',
                trailing: Pressable(
                  semanticLabel: l?.actionSave ?? 'Save',
                  onTap: _save,
                  child: Text(l?.actionSave ?? 'Save',
                      style: F.body.copyWith(
                          color: p.ink, fontWeight: FontWeight.w600)),
                )),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x10),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: S.x4),
                  decoration: moreCard(p),
                  child: Column(children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) Divider(height: S.hair, color: p.line),
                      rows[i],
                    ],
                  ]),
                ),
                const SizedBox(height: S.x3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: S.x4),
                  decoration: moreCard(p),
                  child: _Line('Weight over time',
                      value: null,
                      onTap: () => goto(c, const WeightTrendScreen())),
                ),
                const SizedBox(height: S.x3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.x1),
                  child: Text(
                    'Your strain, calories, heart rate zones and Locus Age '
                    'are worked out from these.',
                    style: F.cap.copyWith(color: p.ink3, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// One line of Edit profile: what it is on the left, its value on the right,
/// a chevron, and the whole line a tap.
class _Line extends StatelessWidget {
  final String label;

  /// Null shows no value at all; empty says "Not set".
  final String? value;
  final VoidCallback onTap;
  const _Line(this.label, {required this.value, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel:
          value == null || value!.isEmpty ? label : '$label, $value',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: S.x12 + S.x2),
        child: Row(children: [
          Text(label, style: F.body.copyWith(color: p.ink)),
          const SizedBox(width: S.x4),
          Expanded(
            child: value == null
                ? const SizedBox.shrink()
                : Text(
                    value!.isEmpty ? 'Not set' : value!,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.num(F.body)
                        .copyWith(color: value!.isEmpty ? p.ink3 : p.ink2),
                  ),
          ),
          const SizedBox(width: S.x2),
          Icon(LucideIcons.chevronRight, size: I.sm, color: p.ink3),
        ]),
      ),
    );
  }
}

// ══════════════════ AUTOMATION ══════════════════
//
// THE TWO PLATFORMS ARE NOT SYMMETRIC AND THIS SCREEN SAYS SO.
//
// Android gets real outbound event triggers: the app broadcasts an intent an
// automation app can start a profile on. iOS does NOT — there is no public
// mechanism for a Shortcuts personal automation to trigger on an arbitrary
// app-donated intent; that trigger list is a fixed system set, and
// `donate`/INInteraction buys Siri suggestions and discoverability, not an
// event trigger. So the iOS half of this screen names what iOS can do (invoke
// the app) and what it cannot (be invoked by it), rather than describing the
// Android feature in language vague enough to read as parity.
//
// And nothing that leaves here is a measurement. A Shortcut that receives
// `readiness=0` has recreated the fabricated-number problem outside the app,
// where there is no tier and no note to explain it — so the one event that
// ships carries facts about the SYNC and no metric at all.

class AutomationSettings extends StatefulWidget {
  const AutomationSettings({super.key});

  @override
  State<AutomationSettings> createState() => _AutomationSettingsState();
}

class _AutomationSettingsState extends State<AutomationSettings> {
  String? _token;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    TaskerBridge.authToken().then((t) {
      if (mounted) setState(() => _token = t);
    });
  }

  Future<void> _copy() async {
    final t = _token;
    if (t == null) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final android = defaultTargetPlatform == TargetPlatform.android;
    final token = _token;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(l?.settingsAutomationNavTitle ?? 'Automation'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                Section(
                  l?.settingsSyncFinishesSectionTitle ??
                      'When a sync finishes',
                  Surface(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            android
                                ? (l?.settingsSyncFinishesAndroidBody ??
                                    'The app broadcasts an intent your automation app can react to. Filter on the action below; it says how many records arrived and when.')
                                : (l?.settingsSyncFinishesIosBody ??
                                    'iOS can’t do this: Shortcuts automations only start on Apple’s own fixed events, and apps can’t add one. This is an iOS limit, not a setting.'),
                            style: F.body.copyWith(color: p.ink2, height: 1.4),
                          ),
                          if (android) ...[
                            const SizedBox(height: S.x3),
                            SelectableText(
                              'wtf.openstrap.openstrap_edge.SYNC_COMPLETE',
                              style: F.cap.copyWith(color: p.ink),
                            ),
                            const SizedBox(height: S.x1),
                            Text(
                                l?.settingsSyncFinishesExtras ??
                                    'Extras: records (int), at (unix seconds)',
                                style: F.over.copyWith(color: p.ink3)),
                          ],
                        ]),
                  ),
                ),
                const SizedBox(height: S.x5),
                Section(
                  l?.settingsNeverSendSectionTitle ?? 'What it will never send',
                  Surface(
                    child: Text(
                      l?.settingsNeverSendBody ??
                          'No recovery, strain or sleep score is sent, on either platform. A missing number would arrive as a bare zero. Sync facts go out, not measurements.',
                      style: F.body,
                    ),
                  ),
                ),
                const SizedBox(height: S.x5),
                Section(
                  l?.settingsBuzzFromShortcutSectionTitle ??
                      'Buzzing the band from a shortcut',
                  Surface(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            android
                                ? (l?.settingsBuzzFromShortcutAndroidBody ??
                                    'Send '
                                        'wtf.openstrap.openstrap_edge.BUZZ_STRAP '
                                        'with this token as the “token” string '
                                        'extra. Without it any app on the phone '
                                        'could buzz your band.')
                                : (l?.settingsBuzzFromShortcutIosBody ??
                                    'This direction works on iOS: a shortcut you '
                                        'run yourself can reach the app. What it '
                                        'cannot do is run itself when the band '
                                        'syncs.'),
                            style: F.body.copyWith(color: p.ink2, height: 1.4),
                          ),
                          if (android) ...[
                            const SizedBox(height: S.x4),
                            if (token == null)
                              Text(
                                  l?.settingsNoTokenYet ??
                                      'No token yet — reopen this screen.',
                                  style: F.cap.copyWith(color: p.ink3))
                            else ...[
                              SelectableText(token,
                                  style: F.cap.copyWith(color: p.ink)),
                              const SizedBox(height: S.x3),
                              BigButton(
                                  _copied
                                      ? (l?.settingsCopied ?? 'Copied')
                                      : (l?.settingsCopyTheToken ??
                                          'Copy the token'),
                                  icon: _copied
                                      ? LucideIcons.check
                                      : LucideIcons.copy,
                                  color: C.dialSleep,
                                  soft: true,
                                  onTap: _copy),
                            ],
                          ],
                        ]),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
