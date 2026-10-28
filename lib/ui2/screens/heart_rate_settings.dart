import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../compute/hr_max.dart' show kManualMaxHrMax, kManualMaxHrMin;
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../grammar.dart' show AppSwitch, Pressable;
import '../theme.dart' show C, F, I, P, R, S;
import '../ui2.dart' show LucideIcons;

class HeartRateSettingsScreen extends StatefulWidget {
  const HeartRateSettingsScreen({super.key});

  @override
  State<HeartRateSettingsScreen> createState() => _HeartRateSettingsScreenState();
}

class _HeartRateSettingsScreenState extends State<HeartRateSettingsScreen> {
  late final TextEditingController _rhrCtrl;
  late final TextEditingController _maxHrCtrl;

  late bool _manual;
  late List<TextEditingController> _minCtrls;
  late List<TextEditingController> _maxCtrls;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final user = app.user ?? const {};
    final rhr = (user['resting_hr'] as num?)?.round() ??
        Prefs.getInt('custom_resting_hr', 57);
    final maxHr = (user['max_hr'] as num?)?.round() ??
        Prefs.getInt('custom_max_hr', 190);

    _rhrCtrl = TextEditingController(text: '$rhr');
    _maxHrCtrl = TextEditingController(text: '$maxHr');

    _manual = Prefs.getBool('manual_hr_zones', false);

    final bounds = (user['hr_zone_bounds'] as List?)
        ?.map((e) => (e as num).toInt())
        .toList();

    final calculated = _calculateZones(rhr, maxHr);

    _minCtrls = [
      for (var i = 0; i < 5; i++)
        TextEditingController(
            text: '${bounds != null && bounds.length == 5 ? bounds[i] : calculated[i].$1}'),
    ];
    _maxCtrls = [
      for (var i = 0; i < 5; i++)
        TextEditingController(
            text: '${i == 4 ? maxHr : (bounds != null && bounds.length == 5 ? bounds[i + 1] - 1 : calculated[i].$2)}'),
    ];

    _rhrCtrl.addListener(_onAnchorsChanged);
    _maxHrCtrl.addListener(_onAnchorsChanged);
  }

  @override
  void dispose() {
    _rhrCtrl.dispose();
    _maxHrCtrl.dispose();
    for (final c in _minCtrls) {
      c.dispose();
    }
    for (final c in _maxCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  List<(int, int)> _calculateZones(int rhr, int maxHr) {
    final hrr = math.max(10, maxHr - rhr);
    final z1Min = (rhr + 0.40 * hrr).round();
    final z1Max = (rhr + 0.60 * hrr).round();

    final z2Min = z1Max + 1;
    final z2Max = (rhr + 0.70 * hrr).round();

    final z3Min = z2Max + 1;
    final z3Max = (rhr + 0.80 * hrr).round();

    final z4Min = z3Max + 1;
    final z4Max = (rhr + 0.90 * hrr).round();

    final z5Min = z4Max + 1;
    final z5Max = maxHr;

    return [
      (z1Min, z1Max),
      (z2Min, z2Max),
      (z3Min, z3Max),
      (z4Min, z4Max),
      (z5Min, z5Max),
    ];
  }

  void _onAnchorsChanged() {
    if (_manual) return;
    final rhr = int.tryParse(_rhrCtrl.text) ?? 57;
    final maxHr = int.tryParse(_maxHrCtrl.text) ?? 190;
    final calculated = _calculateZones(rhr, maxHr);
    for (var i = 0; i < 5; i++) {
      _minCtrls[i].text = '${calculated[i].$1}';
      _maxCtrls[i].text = '${calculated[i].$2}';
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final app = context.read<AppState>();
    final rhr = int.tryParse(_rhrCtrl.text) ?? 57;
    final maxHr = (int.tryParse(_maxHrCtrl.text) ?? 190)
        .clamp(kManualMaxHrMin, kManualMaxHrMax);

    Prefs.setInt('custom_resting_hr', rhr);
    Prefs.setInt('custom_max_hr', maxHr);
    Prefs.setBool('manual_hr_zones', _manual);

    List<int>? bounds;
    if (_manual) {
      bounds = [
        for (var i = 0; i < 5; i++)
          int.tryParse(_minCtrls[i].text) ?? (rhr + i * 15),
      ];
    }

    final currUser = Map<String, dynamic>.from(app.user ?? const {});
    currUser['resting_hr'] = rhr;
    currUser['max_hr'] = maxHr;
    if (bounds != null) {
      currUser['hr_zone_bounds'] = bounds;
    } else {
      currUser.remove('hr_zone_bounds');
    }

    try {
      await app.updateProfile(currUser);
    } catch (_) {}

    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Heart rate zones saved')),
      );
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final zoneColors = [
      C.refZone1, // Zone 1
      C.refZone2, // Zone 2
      C.refZone3, // Zone 3
      C.refZone4, // Zone 4
      C.refZone5, // Zone 5
    ];

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
              child: Row(
                children: [
                  Pressable(
                    onTap: () => Navigator.of(c).maybePop(),
                    semanticLabel: 'Back',
                    child: SizedBox(
                      width: S.tap,
                      height: S.tap,
                      child: Icon(LucideIcons.chevronLeft, size: I.lg, color: p.ink),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'HEART RATE SETTINGS',
                      textAlign: TextAlign.center,
                      style: F.caps.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: S.tap),
                ],
              ),
            ),
            // Body
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: S.x4),
                children: [
                  const SizedBox(height: S.x2),
                  Text(
                    'Heart Rate Zones',
                    style: F.t1.copyWith(color: p.ink, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: S.x2),
                  Text(
                    'Calculated using the scientifically validated heart rate reserve formula, your heart rate (HR) zones are personalized using your baseline resting HR and maximum HR.',
                    style: F.body.copyWith(color: p.ink3, height: 1.4),
                  ),
                  const SizedBox(height: S.x5),
                  // Resting HR & Max HR input cards
                  Row(
                    children: [
                      Expanded(
                        child: _AnchorField(
                          label: 'RESTING HR',
                          controller: _rhrCtrl,
                          infoDialog:
                              'Your lowest heart rate when awake and at rest. Factors into the Karvonen heart rate reserve calculation.',
                        ),
                      ),
                      const SizedBox(width: S.x3),
                      Expanded(
                        child: _AnchorField(
                          label: 'MAX HR',
                          controller: _maxHrCtrl,
                          infoDialog:
                              'Your peak heart rate during all-out maximal exertion. Used to anchor your Zone 5 ceiling.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x6),
                  // Manual toggle row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Manual Heart Rate Zones',
                          style: F.body.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      AppSwitch(
                        _manual,
                        (val) => setState(() {
                          _manual = val;
                          if (!val) _onAnchorsChanged();
                        }),
                        semanticLabel: 'Manual Heart Rate Zones',
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x1),
                  Text(
                    'As your fitness and RHR change, your HR zone ranges are adjusted automatically. You can manually update them if they don\'t feel normal to you.',
                    style: F.cap.copyWith(color: p.ink3, height: 1.35),
                  ),
                  const SizedBox(height: S.x6),
                  // Table Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: S.x2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(
                            'ZONE',
                            style: F.caps.copyWith(color: p.ink3, letterSpacing: .6),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'ZONE MIN',
                            style: F.caps.copyWith(color: p.ink3, letterSpacing: .6),
                          ),
                        ),
                        const SizedBox(width: S.x3),
                        Expanded(
                          child: Text(
                            'ZONE MAX',
                            style: F.caps.copyWith(color: p.ink3, letterSpacing: .6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: S.x3),
                  // Zone Rows 5 down to 1
                  for (var i = 4; i >= 0; i--) ...[
                    if (i < 4) const SizedBox(height: S.x3),
                    _ZoneRow(
                      zoneNumber: i + 1,
                      color: zoneColors[i],
                      minCtrl: _minCtrls[i],
                      maxCtrl: _maxCtrls[i],
                      enabled: _manual,
                    ),
                  ],
                  const SizedBox(height: S.x8),
                ],
              ),
            ),
            // Bottom Save button
            Padding(
              padding: const EdgeInsets.all(S.x4),
              child: Pressable(
                onTap: _saving ? null : _save,
                semanticLabel: 'Save heart rate zones',
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: C.white,
                    borderRadius: R.rMd,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          'SAVE HR ZONES',
                          style: F.caps.copyWith(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnchorField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String infoDialog;

  const _AnchorField({
    required this.label,
    required this.controller,
    required this.infoDialog,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: F.caps.copyWith(color: p.ink3, letterSpacing: .6),
            ),
            const SizedBox(width: S.x1),
            GestureDetector(
              onTap: () => showDialog<void>(
                context: c,
                builder: (_) => AlertDialog(
                  backgroundColor: p.card,
                  title: Text(label, style: F.head.copyWith(color: p.ink)),
                  content: Text(infoDialog, style: F.body.copyWith(color: p.ink2)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(c).pop(),
                      child: Text('OK', style: TextStyle(color: p.ink)),
                    ),
                  ],
                ),
              ),
              child: Icon(LucideIcons.info, size: I.sm, color: p.ink3),
            ),
          ],
        ),
        const SizedBox(height: S.x2),
        Container(
          height: S.x12,
          padding: const EdgeInsets.symmetric(horizontal: S.x3),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: R.rMd,
            border: Border.all(color: p.ink.withValues(alpha: .15)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: F.n24.copyWith(
                      fontSize: 20, color: p.ink, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              Text(
                'bpm',
                style: F.cap.copyWith(color: p.ink3, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ZoneRow extends StatelessWidget {
  final int zoneNumber;
  final Color color;
  final TextEditingController minCtrl;
  final TextEditingController maxCtrl;
  final bool enabled;

  const _ZoneRow({
    required this.zoneNumber,
    required this.color,
    required this.minCtrl,
    required this.maxCtrl,
    required this.enabled,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Row(
      children: [
        // Zone indicator and label
        SizedBox(
          width: 80,
          child: Row(
            children: [
              Container(
                width: 4,
                height: S.x8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: R.rSm,
                ),
              ),
              const SizedBox(width: S.x2),
              Text(
                'Zone $zoneNumber',
                style: F.body.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        // Zone min
        Expanded(
          child: _BpmInput(controller: minCtrl, enabled: enabled),
        ),
        const SizedBox(width: S.x3),
        // Zone max
        Expanded(
          child: _BpmInput(controller: maxCtrl, enabled: enabled),
        ),
      ],
    );
  }
}

class _BpmInput extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;

  const _BpmInput({required this.controller, required this.enabled});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      height: S.x10 + S.x1,
      padding: const EdgeInsets.symmetric(horizontal: S.x3),
      decoration: BoxDecoration(
        color: enabled ? p.card : Color.alphaBlend(p.ink.withValues(alpha: .03), p.card),
        borderRadius: R.rMd,
        border: Border.all(
          color: enabled
              ? p.ink.withValues(alpha: .25)
              : p.ink.withValues(alpha: .08),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: F.body.copyWith(
                color: enabled ? p.ink : p.ink2,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          Text(
            'bpm',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
    );
  }
}
