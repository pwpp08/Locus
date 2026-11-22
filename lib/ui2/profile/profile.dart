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
import '../../community/community_service.dart';
import '../../state/prefs.dart';
import '../community/community.dart' show CommunityScreen;
import '../ui2.dart';
import '../screens/reports.dart' show ReportsScreen;
import '../onboarding/what_to_expect.dart' show WhatToExpectScreen;
import '../../updater/update_service.dart';
import 'data_highlights.dart' show DataHighlightsScreen;
import 'device_settings.dart' show DeviceSettings;
import 'report_issue.dart' show ReportIssueScreen;
import 'settings.dart';
import 'settings_tree.dart';

// ══════════════════ shared list furniture ══════════════════

/// The ground of a More-tab and settings card: the reference's flat slate,
/// its top edge catching the light. No border, no shadow.
BoxDecoration moreCard(P p) => const BoxDecoration(
      borderRadius: ST.r,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [ST.lit, ST.face, ST.face],
        stops: [0, .05, 1],
      ),
    );

/// The name of a row in a settings card: spaced caps, as on the More tab.
TextStyle setRowTitle(P p) => ST.title.copyWith(color: p.ink);

/// One row in a settings list: the same anatomy as a [MoreRow] (an outline
/// glyph, the name in spaced caps) with room for a line under the name and,
/// on the right, a value or a switch. A door has nothing there, as on the
/// reference: the row itself is the door.
class SetRow extends StatelessWidget {
  final IconData? icon;

  /// Kept so existing call sites compile; rows are not tinted by domain.
  final Color color;
  final String title, sub, value;
  final bool danger;
  final VoidCallback? onTap;

  /// Replaces the value.
  final Widget? trailing;

  /// An on/off row: a switch on the right that does what tapping the row
  /// does ([onTap]).
  final bool? switchValue;

  /// The title as written, not in caps: a file name or an id, whose case is
  /// part of it.
  final bool keepCase;

  /// A brand mark in place of [icon] — Lucide has no GitHub/Discord/Reddit
  /// logo, and a generic glyph standing in for one of those is worse than
  /// the extra param. Sized and tinted the same as the [Icon] it replaces.
  final Widget Function(Color tint)? glyph;

  const SetRow(
    IconData this.icon,
    this.color,
    this.title, {
    super.key,
    this.sub = '',
    this.value = '',
    this.danger = false,
    this.trailing,
    this.switchValue,
    this.keepCase = false,
    this.onTap,
  }) : glyph = null;

  const SetRow.brand(
    this.glyph,
    this.color,
    this.title, {
    super.key,
    this.sub = '',
    this.value = '',
    this.danger = false,
    this.onTap,
  })  : icon = null,
        trailing = null,
        switchValue = null,
        keepCase = false;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // A destructive row says so with its glyph, never with red words.
    final mark = danger ? C.danger : ST.glyph;
    final sw = switchValue;
    return Pressable(
      onTap: onTap,
      semanticLabel: sub.isEmpty ? title : '$title. $sub',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ST.rowH),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x2),
          child: Row(
            children: [
              SizedBox(
                width: I.lg + S.x1,
                child: Center(
                  child: glyph != null
                      ? glyph!(mark)
                      : Icon(icon, size: I.lg, color: mark),
                ),
              ),
              const SizedBox(width: S.x5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(keepCase ? title : title.toUpperCase(),
                        style: setRowTitle(p)),
                    if (value.isNotEmpty && bigText(c))
                      Text(value, style: F.cap.copyWith(color: p.ink3)),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: S.half),
                      Text(sub, style: ST.sub.copyWith(color: p.ink2)),
                    ],
                  ],
                ),
              ),
              // THE ROW RULE (see MetricRow): the title is the only flexible
              // part, so every value in a settings list ends on one right edge.
              // The value moves UNDER the title at accessibility sizes instead.
              if (trailing != null) ...[const SizedBox(width: S.x2), trailing!],
              if (trailing == null && sw != null) ...[
                const SizedBox(width: S.x2),
                AppSwitch(sw, onTap == null ? null : (_) => onTap!(),
                    semanticLabel: title),
              ],
              if (trailing == null &&
                  sw == null &&
                  value.isNotEmpty &&
                  !bigText(c)) ...[
                const SizedBox(width: S.x2),
                Text(value, style: F.cap.copyWith(color: p.ink3)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A setting with a few named choices, as one row: the glyph and name, the
/// chosen option on the right with a chevron, and the choices in a dropdown
/// menu ([showChoiceMenu]) when the row is tapped.
class SetDropdown extends StatefulWidget {
  final IconData icon;
  final String title, sub;
  final List<String> options;
  final int index;
  final ValueChanged<int>? onChanged;

  const SetDropdown(this.icon, this.title, this.options, this.index,
      {super.key, this.sub = '', this.onChanged});

  @override
  State<SetDropdown> createState() => _SetDropdownState();
}

class _SetDropdownState extends State<SetDropdown> {
  final _anchor = GlobalKey();

  Future<void> _open() async {
    final at = _anchor.currentContext;
    if (at == null) return;
    final i = await showChoiceMenu(at, widget.options, widget.index);
    if (i != null && i != widget.index) widget.onChanged?.call(i);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final w = widget;
    final chosen = w.index >= 0 && w.index < w.options.length
        ? w.options[w.index]
        : '';
    return SetRow(
      w.icon,
      C.dialStrain,
      w.title,
      sub: w.sub,
      onTap: w.onChanged == null ? null : _open,
      trailing: Row(key: _anchor, mainAxisSize: MainAxisSize.min, children: [
        Text(chosen, style: F.cap.copyWith(color: p.ink2)),
        const SizedBox(width: S.x1),
        Icon(LucideIcons.chevronDown, size: I.sm, color: p.ink3),
      ]),
    );
  }
}

/// A titled run of setting cards, one card per row, [ST.gap] apart, under
/// the reference's heading: flush with the cards, a wide gap above it and a
/// narrower one below.
Widget settingsGroup(BuildContext c, String title, List<Widget> rows) =>
    _group(c, title, [
      for (final r in rows)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: ST.inset),
          decoration: moreCard(P.of(c)),
          child: r,
        ),
    ]);

Widget _group(BuildContext c, String title, List<Widget> rows) => Padding(
      padding: EdgeInsets.only(top: title.isEmpty ? S.x6 : S.x8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x4),
              child: Text(title.toUpperCase(),
                  style: ST.head.copyWith(color: P.of(c).ink2)),
            ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: ST.gap),
            rows[i],
          ],
        ],
      ),
    );

/// One row of the More tab: a card of its own, an outline glyph, the name in
/// spaced caps, a line under it when the name needs one, and at most a short
/// value on the right. Measured off the reference ([ST]).
class MoreRow extends StatelessWidget {
  final IconData? icon;

  /// A brand mark in place of [icon], drawn at the glyph's size and tint.
  final Widget Function(Color tint, double size)? glyph;

  /// A small second glyph on the main one's lower right (a gear on a band:
  /// "the band's settings").
  final IconData? badge;
  final String title, sub, value;
  final VoidCallback? onTap;

  /// An on/off row: an [AppSwitch] on the right that does what tapping the
  /// row does, as on a [SetRow].
  final bool? switchValue;

  const MoreRow(IconData this.icon, this.title,
      {super.key,
      this.badge,
      this.sub = '',
      this.value = '',
      this.switchValue,
      this.onTap})
      : glyph = null;

  const MoreRow.brand(this.glyph, this.title,
      {super.key,
      this.badge,
      this.sub = '',
      this.value = '',
      this.switchValue,
      this.onTap})
      : icon = null;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    const ink = ST.glyph;
    Widget mark = glyph != null
        ? glyph!(ink, I.lg)
        : Icon(icon, size: I.lg, color: ink);
    if (badge != null) {
      mark = SizedBox.square(
        dimension: I.lg + S.x1,
        child: Stack(children: [
          Positioned(left: 0, top: 0, child: mark),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(S.half),
              decoration: BoxDecoration(color: p.card, shape: BoxShape.circle),
              child: Icon(badge, size: I.sm - S.x1, color: ink),
            ),
          ),
        ]),
      );
    }
    return Pressable(
      onTap: onTap,
      semanticLabel: [title, sub, value].where((x) => x.isNotEmpty).join(', '),
      child: Container(
        constraints: const BoxConstraints(minHeight: ST.rowH),
        padding: const EdgeInsets.symmetric(horizontal: ST.inset),
        decoration: moreCard(p),
        child: Row(children: [
          SizedBox(width: I.lg + S.x1, child: Center(child: mark)),
          const SizedBox(width: S.x5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: setRowTitle(p)),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: S.half),
                    Text(sub, style: ST.sub.copyWith(color: p.ink2)),
                  ],
                ],
              ),
            ),
          ),
          if (switchValue != null) ...[
            const SizedBox(width: S.x2),
            AppSwitch(switchValue!, onTap == null ? null : (_) => onTap!(),
                semanticLabel: title),
          ] else if (value.isNotEmpty) ...[
            const SizedBox(width: S.x2),
            Text(value, style: F.cap.copyWith(color: p.ink3)),
          ],
        ]),
      ),
    );
  }
}

/// A titled run of [MoreRow]s, spaced as a [settingsGroup].
Widget moreGroup(BuildContext c, String title, List<Widget> rows) =>
    _group(c, title, rows);

/// Push a screen, keeping the enclosing domain accent. Returns when it pops,
/// so a caller whose own numbers the pushed screen can change is able to
/// re-read them.
Future<void> goto(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

/// The one way into the profile stack from outside it: profile is a pushed
/// route, never a tab.
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
                image: FileImage(File(path)),
                fit: BoxFit.cover,
              ),
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
    return Column(
      children: [
        Pressable(
          semanticLabel: 'Change profile picture',
          onTap: () => _change(c),
          child: Stack(
            children: [
              _PhotoCircle(
                size: size,
                fallback: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.card2,
                  ),
                  child: initial.isEmpty
                      ? Icon(LucideIcons.user, size: I.xl, color: p.ink2)
                      : Text(
                          initial.characters.first.toUpperCase(),
                          style: F.n34.copyWith(color: p.ink),
                        ),
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
            ],
          ),
        ),
        if (initial.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          Text(initial, style: F.t2.copyWith(color: p.ink)),
        ],
      ],
    );
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
  const ProfileAvatar({super.key, this.accent = C.dialStrain, this.size = S.x12});

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
      onTap: () => goto(c, const DataHighlightsScreen()),
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
                  child: Text(
                    initial.characters.first.toUpperCase(),
                    style: F.body.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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

/// What the More tab shows before you open anything: your name.
class ProfileStats {
  final String? name;

  const ProfileStats({this.name});
}

class ProfileHome extends StatefulWidget {
  /// The More tab's root rather than a pushed screen.
  final bool tab;
  const ProfileHome({super.key, this.tab = false});

  @override
  State<ProfileHome> createState() => _ProfileHomeState();
}

class _ProfileHomeState extends State<ProfileHome> {
  /// Re-read after every page this one pushes: an edited name shows the
  /// moment the page closes.
  late Future<ProfileStats> _stats = _load();
  String _version = '';

  @override
  void initState() {
    super.initState();
    readAppVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  Future<ProfileStats> _load() async =>
      ProfileStats(name: context.read<AppState>().user?['name'] as String?);

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
          version: _version,
          onReports: () => _open(c, const ReportsScreen()),
          onCommunity: () => _open(c, const CommunityScreen()),
          onAccount: () => _open(c, const MyAccountSettings()),
          onDevice: () => _open(c, const DeviceSettings()),
          onAppSettings: () => _open(c, const AppSettings()),
          onPrivacy: () => _open(c, const PrivacySettings()),
          onReport: () => _open(c, const ReportIssueScreen()),
          onFirstWeek: () => _open(c, const WhatToExpectScreen()),
          onAbout: () => _open(c, const AboutSettings()),
          onReset: () => confirmReset(c, c.read<AppState>()),
        ),
      );
}

/// The More tab, laid out as the reference's settings: your picture, then
/// your reports and community, then ACCOUNT & SETTINGS and SUPPORT, and the
/// one destructive action at the foot where the reference logs out.
class ProfileHomeView extends StatelessWidget {
  /// Null while the name is still being read.
  final ProfileStats? stats;

  /// `0.9.26 (57)`; the foot line is not drawn until it is known.
  final String version;

  final VoidCallback? onReports,
      onCommunity,
      onAccount,
      onDevice,
      onAppSettings,
      onPrivacy,
      onReport,
      onFirstWeek,
      onAbout,
      onReset;

  /// The More tab: a tab title instead of a back bar.
  final bool tab;

  const ProfileHomeView({
    super.key,
    this.tab = false,
    this.stats,
    this.version = '',
    this.onReports,
    this.onCommunity,
    this.onAccount,
    this.onDevice,
    this.onAppSettings,
    this.onPrivacy,
    this.onReport,
    this.onFirstWeek,
    this.onAbout,
    this.onReset,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final s = stats;
    final list = ListView(
      padding: EdgeInsets.fromLTRB(
          ST.margin, 0, ST.margin, tab ? S.navClear(c) : S.x10),
      children: [
        const SizedBox(height: S.x4),
        ProfilePhotoHeader(name: s?.name),
        const SizedBox(height: S.x2),
        moreGroup(c, '', [
          MoreRow.brand(
              (tint, size) =>
                  StatIcon(StatMark.reports, color: tint, size: size),
              'Reports',
              onTap: onReports),
          // Its unread count, when there is one: the in-app badge.
          ListenableBuilder(
            listenable: CommunityService.instance,
            builder: (c, _) {
              final n = CommunityService.instance.unread;
              return MoreRow.brand(
                  (tint, size) =>
                      StatIcon(StatMark.community, color: tint, size: size),
                  'Community',
                  value: n == 0 ? '' : '${n > 99 ? '99+' : n} new',
                  onTap: onCommunity);
            },
          ),
        ]),
        moreGroup(c, 'Account & settings', [
          MoreRow(LucideIcons.circleUserRound, 'My account',
              onTap: onAccount),
          MoreRow.brand(
              (tint, size) => GearBadged(
                  size: size,
                  color: tint,
                  gap: ST.face,
                  child: StrapIcon(color: tint, height: size)),
              'Device settings',
              onTap: onDevice),
          MoreRow(LucideIcons.clipboardPenLine, 'App settings',
              onTap: onAppSettings),
          MoreRow(LucideIcons.eye, 'Privacy settings', onTap: onPrivacy),
        ]),
        moreGroup(c, 'Support', [
          MoreRow(LucideIcons.bug, 'Report an issue',
              sub: 'Tell us about a bug or anything that looks wrong',
              onTap: onReport),
          MoreRow(LucideIcons.graduationCap, 'First week with Locus',
              onTap: onFirstWeek),
          AnimatedBuilder(
            animation: UpdateService.instance,
            builder: (c, _) => MoreRow.brand(
                (tint, size) => SizedBox.square(
                      dimension: size,
                      child: CustomPaint(
                          painter: LocusMarkPainter(ink: tint)),
                    ),
                'About',
                value: UpdateService.instance.hasUpdate ? 'Update ready' : '',
                onTap: onAbout),
          ),
        ]),
        const SizedBox(height: S.x10),
        Center(
          child: Pressable(
            onTap: onReset,
            semanticLabel: l?.settingsResetAllDataRowTitle ?? 'Reset all data',
            child: Container(
              width: S.x16 * 3 + S.x10 + S.x2,
              height: S.x10,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: R.rPill,
                border: Border.all(color: p.ink3, width: S.half),
              ),
              child: Text(
                  (l?.settingsResetAllDataRowTitle ?? 'Reset all data')
                      .toUpperCase(),
                  style: setRowTitle(p).copyWith(color: p.ink2)),
            ),
          ),
        ),
        if (version.isNotEmpty) ...[
          const SizedBox(height: S.x6),
          Text('APP VERSION: ${version.replaceFirst('(', '(BUILD ')}',
              textAlign: TextAlign.center,
              style: ST.head.copyWith(color: p.ink)),
        ],
        const SizedBox(height: S.x6),
      ],
    );
    // The tab is hosted by the shell's scaffold; the pushed screen brings its
    // own.
    if (tab) return list;
    return settingsGround(
      c,
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(l?.tabMore ?? 'More'),
          ),
          Expanded(child: list),
        ],
      ),
    );
  }
}
