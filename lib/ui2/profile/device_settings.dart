// Device settings: the band, laid out after the reference's device page.
//
// A header that says what is connected (and lets you rename it) and how far
// its data has synced, then two tabs. STATUS is the band itself: a picture
// of it, and its battery. ADVANCED is what can be done to it, one card each
// with a line under it saying what it does.
//
// Left out on purpose, though the reference has them:
//   · Broadcast heart rate. The band's switch for it is a permanent setting
//     the protocol library blocks, its bytes are unconfirmed, and a WHOOP 4.0
//     cannot report whether it is on.
//   · Firmware check, erase device data and reboot. All three are on the
//     dangerous-opcode list (firmware load, force-trim, reboot), which is
//     never sent from a tap in this app.
//   · Regulatory labels and safety statements: they are the band maker's
//     documents, not ours to publish.

import 'dart:convert' show jsonDecode;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart' show LocalDb;
import '../../l10n/app_localizations.dart';
import '../../l10n/date_text.dart' show localizedDate;
import '../../state/app_state.dart';
import '../../state/clock_format.dart' show formatClockOf;
import '../screens/home/home_header.dart' show deviceBatteryOf;
import '../screens/watch_compare_screen.dart' show WatchCompareScreen;
import '../ui2.dart';
import 'band_notifications.dart' show BandNotifications;
import 'devices.dart'
    show
        DeviceDetail,
        MyDevices,
        RePair,
        bandLabelFor,
        confirmForgetBand,
        liveSources,
        renameBand;
import 'gestures.dart' show BandGestures;
import 'profile.dart';

/// The band on the STATUS tab: a product render the user supplied, cut out
/// of its black studio ground (transparent WebP, no maker's mark in frame).
const kBandArt = 'assets/images/band.webp';

class DeviceSettings extends StatefulWidget {
  const DeviceSettings({super.key});

  @override
  State<DeviceSettings> createState() => _DeviceSettingsState();
}

class _DeviceSettingsState extends State<DeviceSettings> {
  /// The firmware the band last reported, from the record the BLE path keeps
  /// (`LocalDb.kBandFirmwareKey`). Null until read, and for a band that has
  /// never said: a WHOOP 4.0 is not asked.
  String? _firmware;

  @override
  void initState() {
    super.initState();
    LocalDb.computeFreshness(LocalDb.kBandFirmwareKey).then((row) {
      final raw = row?['payload_json'];
      if (raw is! String) return;
      final fw = (jsonDecode(raw) as Map?)?['fw'];
      if (fw is String && fw.isNotEmpty && mounted) {
        setState(() => _firmware = fw);
      }
    }).catchError((Object _) {});
  }

  /// Pair a different band: the one paired now is forgotten first, as the
  /// row says, then the picker opens.
  Future<void> _pairAnother(BuildContext c, AppState app, String name) async {
    final nav = Navigator.of(c);
    final choice = await AppDialog.show(c,
        title: 'Pair another band?',
        body: '$name is forgotten first. Everything already saved on this '
            'phone stays.',
        primary: 'Forget and pair',
        secondary: 'Cancel');
    if (choice != DialogChoice.primary) return;
    await app.unpair();
    await nav.push(MaterialPageRoute<void>(builder: (_) => const RePair()));
  }

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final paired = app.isPaired;
    final name = app.strapName ?? 'Your band';
    final battery = deviceBatteryOf(c);
    final band = [
      for (final s in liveSources(app))
        if (s.isBand) s,
    ];
    return DeviceSettingsView(
      paired: paired,
      name: name,
      connected: app.isConnected,
      syncing: app.syncingNow,
      syncedTo: app.lastRecordAt,
      battery: battery?.$1,
      charging: battery?.$2 ?? false,
      model: bandLabelFor(app.device.generation ?? app.paired?.generation),
      serial: app.paired?.serial ?? app.device.serial,
      firmware: _firmware,
      buzzes: defaultTargetPlatform == TargetPlatform.android,
      onInfo: band.isEmpty ? null : () => goto(c, DeviceDetail(band.first)),
      // The name lives on the strap, so a rename needs the link.
      onRename: app.isConnected ? () => renameBand(c, app, name) : null,
      onSync: paired ? app.syncNow : null,
      onPair: paired
          ? () => _pairAnother(c, app, name)
          : () => goto(c, const RePair()),
      onUnpair: paired ? () => confirmForgetBand(c, app, name) : null,
      onOtherDevices: () => goto(c, const MyDevices()),
      onBuzzes: () => goto(c, const BandNotifications()),
      onDoubleTap: () => goto(c, const BandGestures()),
      onCompare: () => goto(c, const WatchCompareScreen()),
    );
  }
}

class DeviceSettingsView extends StatefulWidget {
  final bool paired, connected, syncing, charging;
  final String name;

  /// The newest reading the band has handed over; null before any.
  final DateTime? syncedTo;

  /// 0–100, null when no battery reading is known.
  final double? battery;

  /// The registry's name for the band ("WHOOP 4.0"), its serial and its
  /// firmware: each null when nothing has said, and then not drawn.
  final String? model, serial, firmware;

  /// Band buzzes reads which app notified: an Android capability only.
  final bool buzzes;

  final VoidCallback? onInfo,
      onRename,
      onSync,
      onPair,
      onUnpair,
      onOtherDevices,
      onBuzzes,
      onDoubleTap,
      onCompare;

  /// 0 STATUS, 1 ADVANCED.
  final int initialTab;

  const DeviceSettingsView({
    super.key,
    this.paired = true,
    this.connected = false,
    this.syncing = false,
    this.charging = false,
    this.name = 'Your band',
    this.syncedTo,
    this.battery,
    this.model,
    this.serial,
    this.firmware,
    this.buzzes = true,
    this.onInfo,
    this.onRename,
    this.onSync,
    this.onPair,
    this.onUnpair,
    this.onOtherDevices,
    this.onBuzzes,
    this.onDoubleTap,
    this.onCompare,
    this.initialTab = 0,
  });

  @override
  State<DeviceSettingsView> createState() => _DeviceSettingsViewState();
}

class _DeviceSettingsViewState extends State<DeviceSettingsView> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _topBar(c, p),
          const SizedBox(height: S.x5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x5),
            child: _header(c, p),
          ),
          const SizedBox(height: S.x6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x5),
            child: Row(children: [
              _TabLabel('Status',
                  on: _tab == 0, onTap: () => setState(() => _tab = 0)),
              const SizedBox(width: S.x8),
              _TabLabel('Advanced',
                  on: _tab == 1, onTap: () => setState(() => _tab = 1)),
            ]),
          ),
          Expanded(child: _tab == 0 ? _status(c, p) : _advanced(c, p)),
        ]),
      ),
    );
  }

  Widget _topBar(BuildContext c, P p) => SizedBox(
        height: S.x12,
        child: Row(children: [
          Pressable(
            semanticLabel: 'Close',
            onTap: () => Navigator.of(c).maybePop(),
            child: SizedBox.square(
              dimension: S.tap + S.x4,
              child: Icon(LucideIcons.x, size: I.lg, color: p.ink),
            ),
          ),
          Expanded(
            child: Text('DEVICE SETTINGS',
                textAlign: TextAlign.center, style: setRowTitle(p)),
          ),
          SizedBox.square(
            dimension: S.tap + S.x4,
            child: widget.onInfo == null
                ? null
                : Pressable(
                    semanticLabel: 'About this band',
                    onTap: widget.onInfo,
                    child: Icon(LucideIcons.info, size: I.lg, color: p.ink),
                  ),
          ),
        ]),
      );

  Widget _header(BuildContext c, P p) {
    final w = widget;
    final l = AppLocalizations.of(c);
    final small = F.over.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.4);
    final at = w.syncedTo;
    final when = at == null
        ? '--'
        : '${localizedDate(at, l?.localeName ?? 'en', pattern: 'MMM d')}, '
            '${formatClockOf(at)}';
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              !w.paired
                  ? 'NO BAND PAIRED'
                  : w.connected
                      ? 'CONNECTED TO'
                      : 'NOT CONNECTED',
              style: small.copyWith(
                  color: w.connected ? p.on(C.optimal) : p.ink3)),
          const SizedBox(height: S.x1),
          Row(children: [
            Flexible(
              child: Text(w.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.head.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6)),
            ),
            if (w.onRename != null)
              Pressable(
                semanticLabel: 'Rename the band',
                onTap: w.onRename,
                child: Padding(
                  padding: const EdgeInsets.all(S.x2),
                  child: Icon(LucideIcons.pencil, size: I.md, color: p.ink2),
                ),
              ),
          ]),
        ]),
      ),
      if (w.paired) ...[
        const SizedBox(width: S.x3),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(w.syncing ? 'CATCHING UP' : 'SYNCED TO',
              style: small.copyWith(color: p.ink2)),
          const SizedBox(height: S.half),
          Text(when,
              style: F.num(F.cap)
                  .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
        ]),
        Pressable(
          semanticLabel: 'Sync now',
          onTap: w.onSync,
          child: Padding(
            padding: const EdgeInsets.only(left: S.x3),
            child: Icon(LucideIcons.cloudUpload, size: I.lg, color: p.ink),
          ),
        ),
      ],
    ]);
  }

  /// The band, and its battery in the lower right.
  Widget _status(BuildContext c, P p) {
    final w = widget;
    final pct = w.battery;
    final tone = pct == null
        ? p.ink3
        : pct >= 50
            ? C.recGreen
            : pct >= 20
                ? C.recYellow
                : C.recRed;
    return Stack(children: [
      // Bleeding off the left edge, as the reference's photo does.
      Positioned(
        left: -S.x16,
        right: S.x4,
        top: S.x4,
        bottom: S.x16 + S.x8,
        child: ExcludeSemantics(
          child: Image.asset(kBandArt,
              fit: BoxFit.contain, alignment: Alignment.centerLeft),
        ),
      ),
      Positioned(
        right: S.x5,
        bottom: S.x8,
        child: Semantics(
          label: pct == null ? 'Battery unknown' : 'Battery ${pct.round()}%',
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (w.charging) ...[
                        Icon(LucideIcons.zap, size: I.md, color: tone),
                        const SizedBox(width: S.x1),
                      ],
                      Text(pct == null ? '--' : '${pct.round()}',
                          style: F.n48.copyWith(color: p.ink)),
                      const SizedBox(width: S.x1),
                      Text('%', style: F.n24.copyWith(color: p.ink)),
                    ],
                  ),
                  if (w.model != null)
                    Text(w.model!, style: F.cap.copyWith(color: p.ink3)),
                ]),
                const SizedBox(width: S.x5),
                // The charge as a vertical bar, filled from the foot.
                Container(
                  width: S.x1 + S.half,
                  height: S.x16 * 2 + S.x6,
                  decoration: BoxDecoration(
                      color: p.ink.withValues(alpha: .14),
                      borderRadius: R.rPill),
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: ((pct ?? 0) / 100).clamp(0.0, 1.0),
                    child: Container(
                      decoration:
                          BoxDecoration(color: tone, borderRadius: R.rPill),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  /// One action: its card, and a line under it saying what it does.
  Widget _item(P p, IconData icon, String title, String about,
          VoidCallback? onTap, {IconData? badge}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MoreRow(icon, title, badge: badge, onTap: onTap),
        Padding(
          padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x6),
          child: Text(about,
              style: F.cap.copyWith(color: p.ink3, height: 1.5)),
        ),
      ]);

  Widget _advanced(BuildContext c, P p) {
    final w = widget;
    Widget fact(IconData icon, String label, String value) => Expanded(
          child: Column(children: [
            Icon(icon, size: I.xl, color: p.ink3),
            const SizedBox(height: S.x3),
            Text(label,
                style: F.over.copyWith(
                    color: p.ink3,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4)),
            const SizedBox(height: S.half),
            Text(value,
                textAlign: TextAlign.center,
                style: F.num(F.cap)
                    .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x8, S.x4, S.x10),
      children: [
        if (w.serial != null || w.firmware != null) ...[
          Row(children: [
            if (w.serial != null) fact(LucideIcons.watch, 'DEVICE ID', w.serial!),
            if (w.firmware != null) fact(LucideIcons.cpu, 'FIRMWARE', w.firmware!),
          ]),
          const SizedBox(height: S.x8),
        ],
        _item(
            p,
            LucideIcons.watch,
            w.paired ? 'Pair another band' : 'Pair a band',
            w.paired
                ? 'Pair a different band with Locus. The band paired now is '
                    'forgotten first.'
                : 'Pair your band with Locus.',
            w.onPair,
            badge: LucideIcons.plus),
        if (w.paired)
          _item(
              p,
              LucideIcons.watch,
              'Unpair band',
              'Forget your band in Locus. It stops syncing until you pair it '
                  'again; everything already saved on this phone stays.',
              w.onUnpair,
              badge: LucideIcons.minus),
        _item(
            p,
            LucideIcons.bluetooth,
            'Other devices',
            'Chest straps, rings and scales paired beside the band, and which '
                'one is trusted first.',
            w.onOtherDevices),
        if (w.buzzes)
          _item(p, LucideIcons.vibrate, 'Band buzzes',
              'Which phone notifications the band buzzes for.', w.onBuzzes),
        _item(p, LucideIcons.hand, 'Double-tap',
            'What a double-tap on the band does.', w.onDoubleTap),
        _item(p, LucideIcons.gitCompareArrows, 'Compare with watch',
            'Your band’s numbers next to another watch’s.', w.onCompare),
      ],
    );
  }
}

/// A tab name in caps, underlined while it is the one shown.
class _TabLabel extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _TabLabel(this.label, {required this.on, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: S.tap),
        child: IntrinsicWidth(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label.toUpperCase(),
                  style: F.cap.copyWith(
                      color: on ? p.ink : p.ink3,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: S.x2),
              Container(
                height: S.half + S.hair,
                decoration: BoxDecoration(
                    color: p.ink.withValues(alpha: on ? 1 : 0),
                    borderRadius: R.rPill),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
