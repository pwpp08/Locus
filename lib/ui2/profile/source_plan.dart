// Which device each part of the day comes from: a watch worn through the day
// and a ring worn to bed are two choices, not one.
//
// The pure half ([SourcePlanView]) draws values so the gallery can show every
// state; [SourcePlanScreen] reads the paired wearables and writes the choice
// through `canonical.dart` (`useDevice`, `useSleepDevice`), which re-derives
// the days it moves. Days the primary band recorded always come from the band,
// and the screen says so.

import 'package:flutter/material.dart';

import '../../ble/adapters/_registry.dart' show DeviceCategory, categoryOf;
import '../../compute/inputs/canonical.dart';
import '../../data/db.dart' show LocalDb;
import '../../l10n/display_text.dart';
import '../ui2.dart';
import 'profile.dart';
import 'wearable_numbers.dart' show WearableDisplay;

/// A wearable a part of the day can come from.
typedef PlanDevice = ({String id, String adapter, String label});

class SourcePlanView extends StatelessWidget {
  final List<PlanDevice> devices;

  /// The device chosen for the day, or null for none.
  final String? dayId;

  /// The device chosen for the night; null is "same as daytime".
  final String? nightId;
  final bool busy;
  final ValueChanged<String?>? onDay, onNight;

  const SourcePlanView({
    super.key,
    this.devices = const [],
    this.dayId,
    this.nightId,
    this.busy = false,
    this.onDay,
    this.onNight,
  });

  Widget _row(BuildContext c, String title, bool on, VoidCallback? tap,
      {String sub = ''}) {
    final p = P.of(c);
    return SetRow(
      LucideIcons.circleDot,
      C.dialStrain,
      title,
      sub: sub,
      keepCase: true,
      trailing: on
          ? Icon(LucideIcons.check, size: I.md, color: p.ink)
          : const SizedBox.shrink(),
      onTap: busy ? null : tap,
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(uiText(c, 'Daytime and sleep'),
                sub: uiText(c, 'Which device each number comes from')),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                Text(
                  uiText(c,
                      'Wear a watch by day and a ring to bed? Pick one for each. Days your WHOOP band recorded always come from the band.'),
                  style: F.cap.copyWith(color: p.ink3, height: 1.5),
                ),
                const SizedBox(height: S.x4),
                Section(
                  uiText(c, 'Daytime'),
                  Surface(
                    pad: const EdgeInsets.symmetric(horizontal: S.x4),
                    child: Column(children: [
                      for (final d in devices)
                        _row(c, d.label, dayId == d.id,
                            () => onDay?.call(d.id),
                            sub: uiText(c, 'Steps, heart rate and activity')),
                      _row(c, uiText(c, 'None'), dayId == null,
                          () => onDay?.call(null)),
                    ]),
                  ),
                ),
                Section(
                  uiText(c, 'Sleep'),
                  Surface(
                    pad: const EdgeInsets.symmetric(horizontal: S.x4),
                    child: Column(children: [
                      _row(c, uiText(c, 'Same as daytime'), nightId == null,
                          () => onNight?.call(null)),
                      for (final d in devices)
                        _row(c, d.label, nightId == d.id,
                            () => onNight?.call(d.id),
                            sub: uiText(
                                c, 'Sleep stages, resting heart rate and HRV')),
                    ]),
                  ),
                ),
                const SizedBox(height: S.x4),
                Text(
                  uiText(c,
                      'Choosing a device here turns on “Use this device for scores” for it. Both are experimental until a device has been checked on real hardware.'),
                  style: F.cap.copyWith(color: p.ink3, height: 1.5),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: S.x4),
                    child: Center(
                        child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class SourcePlanScreen extends StatefulWidget {
  const SourcePlanScreen({super.key});

  @override
  State<SourcePlanScreen> createState() => _SourcePlanScreenState();
}

class _SourcePlanScreenState extends State<SourcePlanScreen> {
  List<PlanDevice> _devices = const [];
  String? _day, _night;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await WearableDisplay.instance.loadDevices();
    final day = (await activeWearable())?.$1;
    final raw = await LocalDb.getCursor(kSleepWearableCursor);
    final night = (raw == null || raw.isEmpty || raw == day) ? null : raw;
    if (!mounted) return;
    setState(() {
      _devices = [
        for (final d in WearableDisplay.instance.devices)
          if (categoryOf(d.adapter) == DeviceCategory.wearable)
            (id: d.id, adapter: d.adapter, label: d.label),
      ];
      _day = day;
      _night = night;
    });
  }

  Future<void> _run(Future<void> Function() change) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await change();
    } catch (_) {/* the load below shows what is stored */}
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  String _adapterOf(String id) =>
      _devices.firstWhere((d) => d.id == id).adapter;

  @override
  Widget build(BuildContext c) => SourcePlanView(
        devices: _devices,
        dayId: _day,
        nightId: _night,
        busy: _busy,
        onDay: (id) => _run(() async {
          if (id == null) {
            await setActiveWearable(null);
          } else {
            await useDevice(id, _adapterOf(id), true);
          }
        }),
        onNight: (id) => _run(() async {
          if (id == null) {
            await setSleepWearable(null);
          } else {
            await useSleepDevice(id, _adapterOf(id));
          }
        }),
      );
}
