// Profile, and the More tab.
//
// The same list two ways: pushed from the avatar in a tab's header, and as
// the More tab's root ([ProfileHome.tab]), where it also carries the app
// settings and the doors to what used to be the Activity and Sleep tabs.
//
// The reference design had a Premium badge and a Following/Followers pair.
// Both are gone, and not for lack of screen space: there is no account and no
// social graph, so a follower count would have to be invented and a premium
// tier would have to be sold. What replaces them is what this app actually
// knows — how much it has measured, and from what.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../ui2.dart';
import '../screens/action_sheet.dart' show openCoach;
import '../screens/coach.dart' show CoachSetup, coachSubtitle;
import '../screens/healthspan_screen.dart' show HealthspanScreen;
import '../screens/home_screen.dart'
    show deviceBatteryOf;
import '../screens/milestones_screen.dart' show MilestonesScreen;
import '../screens/watch_compare_screen.dart' show WatchCompareScreen;
import '../screens/wellness_screen.dart' show WellnessScreen;
import 'alarm.dart' show AlarmScreen;
import 'data.dart';
import 'account_screen.dart';
import 'devices.dart';
import 'settings.dart';

// ══════════════════ shared list furniture ══════════════════

/// One row in a settings list. Shared by all three profile screens.
class SetRow extends StatelessWidget {
  final IconData? icon;
  final Color color;
  final String title, sub, value;
  final bool danger, chevron;
  final VoidCallback? onTap;

  /// Replaces the value and chevron (e.g. a [Switch]).
  final Widget? trailing;

  /// A brand mark in place of [icon] — Lucide has no GitHub/Discord/Reddit
  /// logo, and a generic glyph standing in for one of those is worse than
  /// the extra param. Sized and tinted the same as the [Icon] it replaces.
  final Widget Function(Color tint)? glyph;

  const SetRow(IconData this.icon, this.color, this.title,
      {super.key,
      this.sub = '',
      this.value = '',
      this.danger = false,
      this.chevron = true,
      this.trailing,
      this.onTap})
      : glyph = null;

  const SetRow.brand(this.glyph, this.color, this.title,
      {super.key,
      this.sub = '',
      this.value = '',
      this.danger = false,
      this.chevron = true,
      this.onTap})
      : icon = null,
        trailing = null;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: sub.isEmpty ? title : '$title. $sub',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            // A circle, like every icon chip.
            decoration: BoxDecoration(
              color: danger ? p.wash(C.red) : p.card2,
              shape: BoxShape.circle,
            ),
            child: glyph != null
                ? glyph!(danger ? p.on(C.red) : p.ink)
                : Icon(icon, size: I.sm, color: danger ? p.on(C.red) : p.ink),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: F.body.copyWith(color: danger ? p.on(C.red) : p.ink)),
              if (value.isNotEmpty && bigText(c))
                Text(value,
                    style: F.cap.copyWith(
                        color: p.ink3, fontWeight: FontWeight.w600)),
              if (sub.isNotEmpty)
                Text(sub, style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
          // THE ROW RULE (see MetricRow): the title is the only flexible part,
          // so every value in a settings list ends on one right edge. Two flex
          // children would split the width by ratio and break that column.
          // The value moves UNDER the title at accessibility sizes instead —
          // "2026-08-16 04:12" is arbitrary-length, and at 3.1× it pushed
          // itself and the chevron off the right of every settings screen.
          if (trailing != null) ...[
            const SizedBox(width: S.x2),
            trailing!,
          ],
          if (trailing == null && value.isNotEmpty && !bigText(c)) ...[
            const SizedBox(width: S.x2),
            Text(value, style: F.cap.copyWith(color: p.ink3)),
          ],
          if (trailing == null && chevron && !danger) ...[
            const SizedBox(width: S.x2),
            Icon(LucideIcons.chevronRight, size: I.sm, color: p.ink3),
          ],
        ]),
      ),
    );
  }
}

/// A titled card of [SetRow]s, hairline-separated. The hairlines start at
/// the text, not the card edge (grouped lists with inset hairlines).
Widget settingsGroup(BuildContext c, String title, List<Widget> rows) {
  final p = P.of(c);
  return Padding(
    padding: const EdgeInsets.only(top: S.x4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x1, 0, S.x1, S.x2),
            child: Text(
              title,
              style: F.caps.copyWith(color: p.ink3, letterSpacing: 0.5),
            ),
          ),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: S.x2),
            child: Surface(
              pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x1),
              child: rows[i],
            ),
          ),
      ],
    ),
  );
}

/// Push a screen, keeping the enclosing domain accent. Returns when it pops,
/// so a caller whose own numbers the pushed screen can change is able to
/// re-read them.
Future<void> goto(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

/// The one way into the profile stack. [ProfileAvatar] calls this — profile
/// is a pushed route, never a tab.
void openProfile(BuildContext c) => goto(c, const ProfileHome());

/// The account's profile picture: a copy of an image the user picked, kept in
/// the app's own documents folder so it survives the gallery original being
/// deleted. Null when none is set or the file has gone.
class ProfilePhoto {
  ProfilePhoto._();

  static const _key = 'profile.photo_path';

  /// The current file, for every avatar on screen to rebuild from.
  static final ValueNotifier<String?> path = ValueNotifier<String?>(_saved());

  static String? _saved() {
    final p = Prefs.getString(_key, '');
    return p.isNotEmpty && File(p).existsSync() ? p : null;
  }

  /// Ask for an image and make it the picture. False when nothing was
  /// picked. The copy gets a new name each time, so an image cache keyed on
  /// the path never shows the previous picture.
  static Future<bool> pick() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    final src = picked?.files.single.path;
    if (src == null) return false;
    final dir = await getApplicationDocumentsDirectory();
    final ext = src.contains('.') ? src.substring(src.lastIndexOf('.')) : '';
    final dest =
        '${dir.path}/profile_photo_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(src).copy(dest);
    await _replace(dest);
    return true;
  }

  static Future<void> remove() => _replace(null);

  static Future<void> _replace(String? next) async {
    final old = path.value;
    Prefs.setString(_key, next ?? '');
    path.value = next;
    if (old != null && old != next) {
      try {
        await File(old).delete();
      } catch (_) {
        // Already gone: nothing to clean up.
      }
    }
  }
}

/// The picture, cropped to a circle, or [fallback] when there is none.
class _PhotoCircle extends StatelessWidget {
  final double size;
  final Widget fallback;
  const _PhotoCircle({required this.size, required this.fallback});

  @override
  Widget build(BuildContext c) => ValueListenableBuilder<String?>(
        valueListenable: ProfilePhoto.path,
        builder: (c, path, _) => path == null
            ? fallback
            : Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                      image: FileImage(File(path)), fit: BoxFit.cover),
                ),
              ),
      );
}

/// The large avatar at the top of Profile and More: the picture, and the
/// control that sets or changes it.
class ProfilePhotoHeader extends StatelessWidget {
  final String? name;
  const ProfilePhotoHeader({super.key, this.name});

  Future<void> _change(BuildContext c) async {
    final has = ProfilePhoto.path.value != null;
    if (!has) {
      await ProfilePhoto.pick();
      return;
    }
    final choice = await AppDialog.show(
      c,
      title: 'Profile picture',
      body: 'Choose a new picture, or remove this one.',
      primary: 'Choose new',
      destructive: 'Remove',
    );
    if (choice == DialogChoice.primary) await ProfilePhoto.pick();
    if (choice == DialogChoice.destructive) await ProfilePhoto.remove();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final initial = (name ?? '').trim();
    const size = S.x16 + S.x8;
    return Column(children: [
      Pressable(
        semanticLabel: 'Change profile picture',
        onTap: () => _change(c),
        child: Stack(children: [
          _PhotoCircle(
            size: size,
            fallback: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: p.card2),
              child: initial.isEmpty
                  ? Icon(LucideIcons.user, size: I.xl, color: p.ink2)
                  : Text(initial.characters.first.toUpperCase(),
                      style: F.n34.copyWith(color: p.ink)),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: S.x8,
              height: S.x8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.ink,
                border: Border.all(color: p.bg, width: S.half),
              ),
              child: Icon(LucideIcons.camera, size: I.sm, color: p.bg),
            ),
          ),
        ]),
      ),
      if (initial.isNotEmpty) ...[
        const SizedBox(height: S.x3),
        Text(initial, style: F.t2.copyWith(color: p.ink)),
      ],
    ]);
  }
}

/// The way into Profile, in the top-right of every tab. It used to be a gear
/// on Home only, so four tabs out of five had no road to devices, battery,
/// export or settings.
class ProfileAvatar extends StatelessWidget {
  /// The tab's own accent, so the avatar reads as part of the header it sits
  /// in.
  final Color accent;
  final double size;
  const ProfileAvatar({super.key, this.accent = C.domHome, this.size = S.x12});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    String? name;
    try {
      name = c.select<AppState, String?>((a) => a.user?['name'] as String?);
    } catch (_) {
      // No AppState above us (goldens): the plain glyph.
    }
    final initial = (name ?? '').trim();
    // Neutral chrome: the same recessed circle as RoundIconButton, in
    // ink. The tab's accent used to colour it; a domain hue lives
    // in its hero, not its buttons. [accent] is still taken so the six
    // headers that pass it compile.
    return Pressable(
      semanticLabel:
          AppLocalizations.of(c)?.homeProfileSettings ?? 'Profile and settings',
      onTap: () => openProfile(c),
      child: _PhotoCircle(
        size: size,
        fallback: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: p.card2),
          child: initial.isEmpty
              ? Icon(LucideIcons.user, size: I.md, color: p.ink)
              : ExcludeSemantics(
                  child: Text(initial.characters.first.toUpperCase(),
                      style: F.body
                          .copyWith(color: p.ink, fontWeight: FontWeight.w600)),
                ),
        ),
      ),
    );
  }
}

/// Human-readable byte size. No dependency for four lines of arithmetic.
String formatBytes(int b) {
  if (b < 1024) return '$b B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v < 10 ? v.toStringAsFixed(1) : v.round()} ${units[i]}';
}

// ══════════════════ 1 · PROFILE HOME ══════════════════

/// What the profile screen still shows: who you are, how many sources are
/// live, and how much room the data takes.
///
/// The workouts / records / days / sessions counters are gone with the tile
/// that displayed them. They cost a `getRecords()` and a whole year-of-workouts
/// query on every open, so leaving the fields behind would have kept paying for
/// numbers nobody reads.
class ProfileStats {
  final String? name;
  final int sources;
  final int? storageBytes;

  const ProfileStats({this.name, this.sources = 0, this.storageBytes});
}

class ProfileHome extends StatefulWidget {
  /// The More tab's root rather than a pushed screen.
  final bool tab;
  const ProfileHome({super.key, this.tab = false});

  @override
  State<ProfileHome> createState() => _ProfileHomeState();
}

class _ProfileHomeState extends State<ProfileHome> {
  /// Re-read after every screen this one pushes. It used to be a single
  /// `late final` Future, so pairing a band from My sources (which auto-pops
  /// straight back here) left the row reading "0 sources", and an import or a
  /// reset left Storage on the old size until the screen was left and
  /// re-entered.
  late Future<ProfileStats> _stats = _load();

  Future<ProfileStats> _load() async {
    final app = context.read<AppState>();
    final repo = app.repo;
    final sources = liveSources(app).length;
    if (repo == null) {
      return ProfileStats(
          name: app.user?['name'] as String?, sources: sources);
    }
    final bytes = await app.dataFileBytes();
    return ProfileStats(
      name: app.user?['name'] as String?,
      sources: sources,
      storageBytes: bytes,
    );
  }

  Future<void> _open(BuildContext c, Widget w) async {
    await goto(c, w);
    // A block body, not `=>`: the arrow form returns the assigned Future, which
    // setState asserts against (debug builds throw and skip the rebuild).
    if (!mounted) return;
    setState(() {
      _stats = _load();
    });
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<ProfileStats>(
        future: _stats,
        builder: (c, snap) => ProfileHomeView(
          tab: widget.tab,
          stats: snap.data,
          onDevices: () => _open(c, const MyDevices()),
          onSettings: () => _open(c, const MoreSettings()),
          onExport: () => _open(c, const DataScreen()),
          onEdit: () => _open(c, const EditProfile()),
          onCoach: () => _open(c, const CoachSetup()),
        ),
      );
}

class ProfileHomeView extends StatelessWidget {
  /// Null while the counts are still being read — the numbers are absent, not
  /// zero, and a zero rendered during a load is a wrong number on screen.
  final ProfileStats? stats;
  final VoidCallback? onDevices, onSettings, onExport, onEdit, onCoach;

  /// The More tab: a tab title instead of a back bar, and the app settings.
  final bool tab;

  const ProfileHomeView(
      {super.key,
      this.tab = false,
      this.stats,
      this.onDevices,
      this.onCoach,
      this.onSettings,
      this.onExport,
      this.onEdit,
      });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final s = stats;
    final list = ListView(
              padding: EdgeInsets.fromLTRB(
                  S.x4, 0, S.x4, tab ? S.navClear(c) : S.x10),
              children: [
                const SizedBox(height: S.x4),
                ProfilePhotoHeader(name: s?.name),
                const SizedBox(height: S.x2),
                if (tab) ...[
                  settingsGroup(c, 'Insights & coaching', [
                    SetRow(LucideIcons.sparkles, C.purple,
                        AppLocalizations.of(c)?.profileAiCoach ?? 'AI coach',
                        sub: coachSubtitle(c) ??
                            'Chat, recommendations and daily briefings',
                        onTap: () => openCoach(c)),
                    SetRow(LucideIcons.calendarDays, C.green,
                        'Habit tracker',
                        sub: 'Daily habits, journals and impacts',
                        onTap: () => goto(c, const WellnessScreen(initialTab: 2))),
                    SetRow(LucideIcons.activity, C.blue,
                        'Healthspan',
                        sub: 'Biological age, cardiovascular & cellular health',
                        onTap: () => goto(c, const HealthspanScreen())),
                    SetRow(LucideIcons.watch, C.lavender,
                        'Compare with watch',
                        sub: 'Side-by-side data with Apple Watch or Garmin',
                        onTap: () => goto(c, const WatchCompareScreen())),
                    SetRow(LucideIcons.trophy, C.amber,
                        'Milestones',
                        sub: 'Lifetime achievements and personal records',
                        onTap: () => goto(c, const MilestonesScreen())),
                  ]),
                ],
                settingsGroup(c, l?.profileQuickAccessGroup ?? 'Quick access', [
                  // The band's battery rides the devices row: Profile is
                  // where "is my band all right?" is asked from every tab.
                  Builder(builder: (c) {
                    final battery = deviceBatteryOf(c);
                    return SetRow(LucideIcons.watch, C.blue,
                        l?.profileMyDevices ?? 'My devices',
                        sub: [
                          if (s != null)
                            l?.profileSourcesCount(s.sources) ??
                                '${s.sources} source${s.sources == 1 ? '' : 's'}',
                          if (battery != null)
                            l?.profileBandBattery(battery.$1.round()) ??
                                'Band ${battery.$1.round()}%',
                        ].join(' · '),
                        onTap: onDevices);
                  }),
                  SetRow(LucideIcons.alarmClock, C.lavender,
                      l?.settingsAlarmRowTitle ?? 'Alarm',
                      sub: l?.settingsAlarmRowSub ??
                          'Buzzes on your wrist, on the band’s own clock',
                      onTap: () => goto(c, const AlarmScreen())),
                  SetRow(LucideIcons.userPen, C.purple,
                      l?.profileEditProfile ?? 'Edit profile',
                      sub: l?.profileEditProfileSub ??
                          'Sex, age, height, weight',
                      onTap: onEdit),
                ]),
                settingsGroup(c, l?.profileYourDataGroup ?? 'Your data', [
                  SetRow(LucideIcons.cloud, C.blue,
                      'Cloud account',
                      sub: 'Online backup and data sync',
                      onTap: () => goto(c, const AccountScreen())),
                  SetRow(LucideIcons.database, C.green,
                      l?.profileStorage ?? 'Storage',
                      value: s?.storageBytes == null
                          ? ''
                          : formatBytes(s!.storageBytes!),
                      chevron: false),
                  // Export straight from here: it used to be five taps deep,
                  // behind a row named for its position ("More settings").
                  SetRow(LucideIcons.download, C.green,
                      l?.profileExportRow ?? 'Export and backup',
                      sub: l?.profileExportRowSub ??
                          'Spreadsheets, a full copy, and bringing history in',
                      onTap: onExport),
                ]),
              ],
            );
    // The tab is hosted by the shell's scaffold; the pushed screen brings its
    // own.
    if (tab) return list;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(l?.profileTitle ?? 'Profile'),
          ),
          Expanded(child: list),
        ]),
      ),
    );
  }

}
