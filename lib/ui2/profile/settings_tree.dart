// The settings tree, laid out as the reference lays out its own: the More
// tab's doors lead to My account, Device settings, App settings and Privacy
// settings, and App settings to activity, the AI, data export, integrations,
// notifications and units. Every page is a [settingsPage] of [settingsGroup]s,
// measured off the reference ([ST]).
//
// Left out on purpose: membership, gifts, payment and a password. There is no
// account to bill or to sign into; the one account there is (the community's)
// is optional and lives under My account.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/coach_config.dart';
import '../../coach/coach_memory.dart';
import '../../coach/coach_style.dart';
import '../../ai/briefing.dart' show OutlookLength;
import '../../community/community_service.dart';
import '../../telemetry/health_uploader.dart'
    show kHealthDataContributionEnabled;
import '../../l10n/app_localizations.dart';
import '../../live/live_activity.dart';
import '../../notify/notification_prefs.dart';
import '../../state/app_state.dart';
import '../../state/clock_format.dart';
import '../../state/units_controller.dart';
import '../community/community.dart' show CommunityScreen;
import 'import_hub.dart' show ImportHubScreen;
import '../screens/coach.dart' show CoachSetup, openCoachSheet;
import '../screens/coach_memory_screen.dart' show CoachMemoryScreen;
import '../screens/heart_rate_settings.dart' show HeartRateSettingsScreen;
import '../ui2.dart';
import 'profile.dart';
import 'settings.dart';
import 'whoop_import_screen.dart';

// ══════════════════ MY ACCOUNT ══════════════════

/// You: the profile the numbers are scored against, and the optional
/// community account.
class MyAccountSettings extends StatelessWidget {
  const MyAccountSettings({super.key});

  @override
  Widget build(BuildContext c) => ListenableBuilder(
        listenable: CommunityService.instance,
        builder: (c, _) {
          final cs = CommunityService.instance;
          final email = cs.user?.email ?? '';
          return settingsPage(c, 'My account', [
            settingsGroup(c, 'Personal information', [
              SetRow(LucideIcons.circleUserRound, C.dialStrain,
                  'Profile information',
                  sub: 'Name, age, sex, height and weight',
                  onTap: () => goto(c, const EditProfile())),
            ]),
            settingsGroup(c, 'Locus account', [
              SetRow(LucideIcons.mail, C.dialStrain,
                  cs.signedIn && email.isNotEmpty ? 'Email' : 'Locus account',
                  sub: cs.signedIn
                      ? (email.isNotEmpty ? email : 'Signed in')
                      : 'Optional: teams, leaderboards and chat',
                  onTap: () => goto(c, const CommunityScreen())),
            ]),
          ]);
        },
      );
}

// ══════════════════ APP SETTINGS ══════════════════

/// How the app behaves: one door per subject, as on the reference.
class AppSettings extends StatelessWidget {
  const AppSettings({super.key});

  @override
  Widget build(BuildContext c) => settingsPage(c, 'App settings', [
        const SizedBox(height: S.x6),
        moreGroup(c, '', [
          MoreRow.brand(
              (t, s) => GearBadged(
                  size: s,
                  color: t,
                  gap: ST.face,
                  child: Icon(LucideIcons.heartPulse, size: s, color: t)),
              'Activity settings',
              onTap: () => goto(c, const ActivitySettings())),
          MoreRow.brand((t, s) => CoachMark(size: s, color: t), 'AI settings',
              onTap: () => goto(c, const AiSettings())),
          MoreRow(LucideIcons.importBox, 'Data export',
              onTap: () => goto(c, const YourDataSettings())),
          MoreRow(LucideIcons.link2, 'Integrations',
              onTap: () => goto(c, const IntegrationsSettings())),
          MoreRow(LucideIcons.bell, 'Notifications',
              onTap: () => goto(c, const NotificationSettings())),
          MoreRow(LucideIcons.ruler, 'Units and time',
              onTap: () => goto(c, const UnitsSettings())),
        ]),
      ]);
}

/// What counts as an activity, and the zones it is scored in.
class ActivitySettings extends StatelessWidget {
  const ActivitySettings({super.key});

  @override
  Widget build(BuildContext c) => settingsPage(c, 'Activity settings', [
        const SizedBox(height: S.x6),
        moreGroup(c, '', [
          MoreRow.brand((t, s) => ActivityFigure(size: s, color: t),
              'Activity detection',
              onTap: () => goto(c, const ActivityDetectionScreen())),
          MoreRow(LucideIcons.heart, 'Heart rate settings',
              onTap: () => goto(c, const HeartRateSettingsScreen())),
          MoreRow(LucideIcons.smartphone, 'Live activity',
              onTap: () => goto(c, const LiveActivitySettings())),
        ]),
      ]);
}

/// The live workout on the lock screen: on or off, and on Android 16 and up
/// whether it is promoted to a Live Update with its status bar chip.
class LiveActivitySettings extends StatefulWidget {
  const LiveActivitySettings({super.key});

  @override
  State<LiveActivitySettings> createState() => _LiveActivitySettingsState();
}

class _LiveActivitySettingsState extends State<LiveActivitySettings> {
  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return settingsPage(c, 'Live activity', [
      const SizedBox(height: S.x4),
      SwitchHead('Live activity', LiveActivity.enabled,
          onTap: () =>
              setState(() => LiveActivity.enabled = !LiveActivity.enabled)),
      const SizedBox(height: S.x2),
      Text(
        'While a workout runs, show your heart rate, zone and time on the '
        'lock screen and in the notification shade. Distance and pace join '
        'them on a route.',
        style: F.cap.copyWith(color: p.ink3, height: 1.5),
      ),
      const SizedBox(height: S.x4),
      const DashedRule(),
      const SizedBox(height: S.x6),
      SwitchHead('Status bar chip', LiveActivity.chip,
          onTap: !LiveActivity.enabled
              ? null
              : () => setState(() => LiveActivity.chip = !LiveActivity.chip)),
      const SizedBox(height: S.x2),
      Text(
        'Android 16 and up: keep the workout in a chip beside the clock, '
        'and in the Now Bar on phones that have one. Android draws that '
        'notification itself; turn this off to keep the Locus card instead. '
        'Applies from the next workout.',
        style: F.cap.copyWith(color: p.ink3, height: 1.5),
      ),
    ]);
  }
}

/// The detector's switch, what it looks for, and a picture of it: a stretch
/// of raised heart rate held long enough to count.
class ActivityDetectionScreen extends StatefulWidget {
  const ActivityDetectionScreen({super.key});

  @override
  State<ActivityDetectionScreen> createState() =>
      _ActivityDetectionScreenState();
}

class _ActivityDetectionScreenState extends State<ActivityDetectionScreen> {
  NotificationPrefs? _prefs;

  @override
  void initState() {
    super.initState();
    NotificationPrefs.load().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  Future<void> _toggle() async {
    final now = _prefs;
    if (now == null) return;
    final next = now.copyWith(autoDetectEnabled: !now.autoDetectEnabled);
    setState(() => _prefs = next);
    await next.save();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final on = _prefs?.autoDetectEnabled ?? false;
    return settingsGround(
      c,
      Column(children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: S.x4),
          child: NavBar('Activity detection'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(ST.margin, S.x4, ST.margin, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchHead('Activity detection', on,
                  onTap: _prefs == null ? null : _toggle),
              const SizedBox(height: S.x3),
              Text(
                'Find the parts of your day when your heart worked hard '
                'enough, for long enough, to count as an activity, and '
                'tell you so you can log it.',
                style: F.cap.copyWith(color: p.ink3, height: 1.5),
              ),
            ],
          ),
        ),
        const Spacer(),
        const AspectRatio(aspectRatio: 393 / 180, child: DetectionPicture()),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              ST.margin, S.x8, ST.margin, S.x12),
          child: Text(
            'An activity is suggested when your heart rate stays well above '
            'its resting level for at least 12 minutes.',
            textAlign: TextAlign.center,
            style: F.head
                .copyWith(color: p.ink, fontWeight: FontWeight.w400, height: 1.3),
          ),
        ),
      ]),
    );
  }
}

/// A page's leading switch as the reference sets one: the name in spaced
/// caps on the left, the switch on the right.
class SwitchHead extends StatelessWidget {
  final String title;
  final bool value;
  final VoidCallback? onTap;

  const SwitchHead(this.title, this.value, {super.key, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Row(children: [
      Expanded(
        child: Text(title.toUpperCase(), style: setRowTitle(p)),
      ),
      AppSwitch(value, onTap == null ? null : (_) => onTap!(),
          semanticLabel: title),
    ]);
  }
}

/// The detection picture: a day's heart rate, flat but for one stretch
/// raised and held, that stretch filled and measured, and the activity's
/// marker over it.
class DetectionPicture extends StatelessWidget {
  const DetectionPicture({super.key});

  @override
  Widget build(BuildContext c) => LayoutBuilder(builder: (c, box) {
        final w = box.maxWidth;
        final mark = S.x10 + S.x1;
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
              child: CustomPaint(painter: _DetectionPainter(P.of(c)))),
          // The marker's pointer, under it, aimed at the block.
          Positioned(
            left: w * .45 - S.x1 - S.half,
            top: mark - S.x1,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: const SizedBox.square(
                dimension: S.x2 + S.half,
                child: ColoredBox(color: C.dialStrain),
              ),
            ),
          ),
          Positioned(
            left: w * .45 - mark / 2,
            top: 0,
            child: Container(
              width: mark,
              height: mark,
              decoration: const BoxDecoration(
                  color: C.dialStrain, borderRadius: R.rSm),
              alignment: Alignment.center,
              child: ActivityFigure(size: I.lg + S.x1, color: P.of(c).ink),
            ),
          ),
        ]);
      });
}

class _DetectionPainter extends CustomPainter {
  final P p;
  const _DetectionPainter(this.p);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final r = math.Random(7);
    final base = h * .78, high = h * .42;
    final from = w * .33, to = w * .57;
    // The day: a jagged line near the floor, one block raised between
    // [from] and [to].
    final line = Path();
    final fill = Path();
    var filling = false;
    for (var x = 0.0; x <= w; x += w / 160) {
      final inside = x >= from && x <= to;
      // Busy outside: noise, the odd spike, and a few slower swells.
      final spike = r.nextDouble() < .08 ? r.nextDouble() * h * .28 : 0.0;
      final swell = math.max(0.0, math.sin(x / w * 19)) * h * .1;
      // Inside, a first step a little lower, then the held plateau.
      final step = x < from + (to - from) * .28 ? h * .1 : 0.0;
      final y = inside
          ? high + step + (r.nextDouble() - .5) * h * .07
          : base - r.nextDouble() * h * .06 - spike - swell;
      if (x == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
      if (inside) {
        if (!filling) fill.moveTo(x, base + h * .06);
        filling = true;
        fill.lineTo(x, y);
      }
    }
    fill
      ..lineTo(to, base + h * .06)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              C.dialStrain.withValues(alpha: .55),
              C.dialStrain.withValues(alpha: .08),
            ],
          ).createShader(Rect.fromLTRB(from, high, to, base)));
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(from, 0, to, h));
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = S.hair * 1.5
          ..color = C.dialStrain);
    canvas.restore();
    for (final clip in [
      Rect.fromLTRB(0, 0, from, h),
      Rect.fromLTRB(to, 0, w, h),
    ]) {
      canvas.save();
      canvas.clipRect(clip);
      canvas.drawPath(
          line,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = S.hair
            ..color = p.ink3);
      canvas.restore();
    }
    // The measure under the block: a dashed bracket and its length.
    final y = base + h * .1;
    final dash = Paint()
      ..color = p.ink2
      ..strokeWidth = S.hair * 1.5;
    for (var x = from; x < to; x += S.x2) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + S.x1, to), y), dash);
    }
    canvas.drawLine(Offset(from, y - S.x1), Offset(from, y + S.x1), dash);
    canvas.drawLine(Offset(to, y - S.x1), Offset(to, y + S.x1), dash);
    final tp = TextPainter(
      text: TextSpan(
          text: '12 min +',
          style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((from + to - tp.width) / 2, y - tp.height - S.x1));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_DetectionPainter old) => false;
}

// ══════════════════ AI SETTINGS ══════════════════

/// Everything about the coach's chat, with the model it runs on at the foot:
/// the provider is set once, the rest is tuned often.
class AiSettings extends StatefulWidget {
  const AiSettings({super.key});

  @override
  State<AiSettings> createState() => _AiSettingsState();
}

class _AiSettingsState extends State<AiSettings> {
  void _openMemory(BuildContext c) {
    final key = (c.read<AppState>().user?['id'] ?? 'local').toString();
    goto(
      c,
      CoachMemoryScreen(
        storageKey: key,
        onOpenChat: (id) => openCoachSheet(c, sessionId: id),
        onSnapshot: () => openCoachSheet(c,
            initialMessage: 'Give me a snapshot of what you know about me: '
                'my goals, how I like to be coached, and my routine.'),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final cfg = c.watch<CoachConfig>();
    final host = Uri.tryParse(cfg.baseUrl)?.host ?? '';
    return settingsPage(c, 'AI settings', [
      const SizedBox(height: S.x4),
      SwitchHead('Memory', CoachMemory.enabled,
          onTap: () =>
              setState(() => CoachMemory.enabled = !CoachMemory.enabled)),
      const SizedBox(height: S.x2),
      Text(
        'Let the coach remember details from your chats to tailor its '
        'advice. The notes stay on this phone, and you can read or delete '
        'each one.',
        style: F.cap.copyWith(color: p.ink3, height: 1.5),
      ),
      const SizedBox(height: S.x4),
      const DashedRule(),
      settingsGroup(c, 'Chat', [
        SetDropdown(
          LucideIcons.ruler,
          'Answer length',
          [for (final x in CoachLength.values) x.label],
          CoachStyle.length.index,
          sub: 'How much each chat answer says',
          onChanged: (i) =>
              setState(() => CoachStyle.length = CoachLength.values[i]),
        ),
        SetDropdown(
          LucideIcons.messageSquare,
          'Tone',
          [for (final x in CoachTone.values) x.label],
          CoachStyle.tone.index,
          sub: 'How the coach talks to you',
          onChanged: (i) =>
              setState(() => CoachStyle.tone = CoachTone.values[i]),
        ),
        SetRow(LucideIcons.smile, C.dialStrain, 'Emojis',
            sub: 'Let answers use a few emojis',
            switchValue: CoachStyle.emojis,
            onTap: () =>
                setState(() => CoachStyle.emojis = !CoachStyle.emojis)),
        SetRow(LucideIcons.bookOpen, C.dialStrain, 'My memory',
            sub: 'What it knows about you, and past chats',
            onTap: () => _openMemory(c)),
      ]),
      settingsGroup(c, 'Daily outlook', [
        SetDropdown(
          LucideIcons.sun,
          'Outlook length',
          [for (final x in OutlookLength.values) x.label],
          OutlookLength.current.index,
          sub: 'How much the Daily Outlook says',
          onChanged: (i) =>
              setState(() => OutlookLength.set(OutlookLength.values[i])),
        ),
      ]),
      settingsGroup(c, 'AI button', [
        SetRow(LucideIcons.messageCircle, C.dialStrain, 'AI button',
            sub: 'The floating button that opens the coach anywhere',
            onTap: () => goto(c, const AiButtonSettings())),
      ]),
      const SizedBox(height: S.x8),
      InfoCard(
        'Data privacy',
        'Your questions, and the numbers the coach looks up to answer them, '
            'go only to the provider below, with your own key. Nothing '
            'passes through Locus on the way.',
        link: 'Learn more',
        onLink: () => goto(c, const PrivacySettings()),
      ),
      settingsGroup(c, 'Provider', [
        SetRow.brand((t) => CoachMark(size: I.lg, color: t), C.dialStrain,
            'Provider and model',
            sub: cfg.configured
                ? [cfg.model, host].where((x) => x.isNotEmpty).join(' · ')
                : 'Not set up. Add a provider to turn the coach on',
            onTap: () => goto(c, const CoachSetup())),
      ]),
    ]);
  }
}

/// The reference's dotted rule under a page's leading switch.
class DashedRule extends StatelessWidget {
  const DashedRule({super.key});

  @override
  Widget build(BuildContext c) => SizedBox(
        height: S.hair,
        width: double.infinity,
        child: CustomPaint(painter: _DashPainter(P.of(c).ink3)),
      );
}

class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = S.hair;
    for (var x = 0.0; x < s.width; x += S.x1 + S.half) {
      canvas.drawLine(Offset(x, 0), Offset(x + S.half, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// A titled note on a card, as the reference's Data privacy card: a short
/// title, a paragraph, and an optional link in spaced caps with an arrow.
class InfoCard extends StatelessWidget {
  final String title, body, link;
  final IconData? icon;
  final VoidCallback? onLink;

  const InfoCard(this.title, this.body,
      {super.key, this.link = '', this.icon, this.onLink});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      padding: const EdgeInsets.all(S.x5),
      decoration: moreCard(p).copyWith(borderRadius: R.rLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[
              Icon(icon, size: I.md, color: p.ink2),
              const SizedBox(width: S.x2),
            ],
            Expanded(
              child: Text(title,
                  style: F.head
                      .copyWith(color: p.ink, fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: S.x3),
          Text(body, style: F.cap.copyWith(color: p.ink2, height: 1.5)),
          if (link.isNotEmpty) ...[
            const SizedBox(height: S.x4),
            Pressable(
              onTap: onLink,
              semanticLabel: link,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(link.toUpperCase(), style: setRowTitle(p))),
                const SizedBox(width: S.x2),
                Icon(LucideIcons.arrowRight, size: I.md, color: p.ink),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════ INTEGRATIONS ══════════════════

/// What this app exchanges data with: the phone's health store, a WHOOP
/// export coming in, and automation apps.
class IntegrationsSettings extends StatelessWidget {
  const IntegrationsSettings({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final l = AppLocalizations.of(c);
    final store = app.healthStoreName;
    return settingsPage(c, 'Integrations', [
      settingsGroup(c, 'Health store', [
        SetRow(LucideIcons.heartPulse, C.dialStrain,
            l?.settingsWriteToHealthStoreRowTitle(store) ?? 'Write to $store',
            sub: healthSyncSub(c, app.healthSyncEnabled, app.healthState, store),
            switchValue: app.healthSyncEnabled,
            onTap: () => toggleHealthSync(app)),
      ]),
      settingsGroup(c, 'Other apps', [
        SetRow(LucideIcons.download, C.dialStrain, 'Import your history',
            sub: '$store and Strava: workouts, sleep, steps and heart rate',
            onTap: () => goto(c, const ImportHubScreen())),
        SetRow(LucideIcons.upload, C.dialStrain, 'Import WHOOP data',
            sub: 'Your recovery, sleep, strain and workouts from a WHOOP '
                'export',
            onTap: () => goto(c, const WhoopImportScreen())),
        SetRow(LucideIcons.workflow, C.dialStrain,
            l?.settingsTaskerShortcutsRowTitle ?? 'Tasker and Shortcuts',
            sub: l?.settingsTaskerShortcutsRowSub ??
                'Android only for events out. iOS can buzz the band '
                    'but cannot be triggered by it',
            onTap: () => goto(c, const AutomationSettings())),
      ]),
    ]);
  }
}

// ══════════════════ UNITS AND TIME ══════════════════

class UnitsSettings extends StatelessWidget {
  const UnitsSettings({super.key});

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final units = c.watch<UnitsController>();
    final clock = c.watch<ClockFormatController>();
    final app = c.read<AppState>();
    return settingsPage(c, 'Units and time', [
      settingsGroup(c, '', [
        SetDropdown(
            LucideIcons.ruler,
            l?.settingsUnitsRowTitle ?? 'Units',
            const ['Metric', 'Imperial'],
            units.system.label == 'Imperial' ? 1 : 0,
            onChanged: (i) => units.setSystem(UnitSystem.values[i])),
        SetDropdown(
            LucideIcons.clock,
            l?.settingsClockFormatRowTitle ?? 'Time format',
            [
              l?.settingsClockFormatSystem ?? ClockFormat.system.label,
              l?.settingsClockFormat24h ?? ClockFormat.h24.label,
              l?.settingsClockFormat12h ?? ClockFormat.h12.label,
            ],
            clock.format.index,
            // The wind-down body bakes the time in when it's armed: re-arm it.
            onChanged: (i) async {
              try {
                await clock.setFormat(ClockFormat.values[i]);
              } finally {
                await app.refreshAiReminders();
              }
            }),
      ]),
    ]);
  }
}

// ══════════════════ PRIVACY SETTINGS ══════════════════

/// The two things that can send anything about you anywhere, as switches,
/// then plainly what this app does and does not do with your data.
class PrivacySettings extends StatelessWidget {
  const PrivacySettings({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final l = AppLocalizations.of(c);
    final showShare = kHealthDataContributionEnabled || app.healthShareConsent;
    return settingsPage(c, 'Privacy settings', [
      settingsGroup(c, 'What you share', [
        SetRow(LucideIcons.bug, C.dialStrain,
            l?.settingsCrashReportsRowTitle ?? 'Crash reports',
            sub: l?.settingsCrashReportsRowSub ??
                'Nothing is sent until you say so',
            switchValue: app.telemetryConsent,
            onTap: () => app.setTelemetryConsent(!app.telemetryConsent)),
        if (showShare)
          SetRow(LucideIcons.cloudUpload, C.dialStrain,
              l?.settingsContributeHealthDataRowTitle ??
                  'Contribute my health data',
              sub: l?.settingsContributeHealthDataRowSub ??
                  'Uploads your whole database once a day, on '
                      'Wi-Fi and charging, to improve the algorithms',
              switchValue: app.healthShareConsent,
              onTap: () => toggleHealthShare(c, app)),
      ]),
      settingsGroup(c, 'How Locus treats your data', [
        for (final (icon, title, body) in kPrivacyFacts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: I.lg + S.x1,
                  child: Icon(icon, size: I.lg, color: P.of(c).ink2),
                ),
                const SizedBox(width: S.x5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title.toUpperCase(),
                          style: setRowTitle(P.of(c))),
                      const SizedBox(height: S.x1),
                      Text(body,
                          style: F.cap
                              .copyWith(color: P.of(c).ink2, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ]),
    ]);
  }
}

/// What the privacy page says, each line something the code does. Kept as
/// data so a test can hold it to the build.
const kPrivacyFacts = <(IconData, String, String)>[
  (
    LucideIcons.smartphone,
    'Kept on this phone',
    'Everything your band records, and every score worked out from it, is '
        'stored in a database on this phone. There is no Locus server '
        'holding your health data, and you need no account to use the app.',
  ),
  (
    LucideIcons.cpu,
    'Worked out on this phone',
    'Sleep, recovery, strain and stress are calculated on the phone itself. '
        'Your raw heart data is never sent anywhere to be scored.',
  ),
  (
    LucideIcons.messageSquare,
    'The coach uses your own provider',
    'The coach is off until you add an AI provider with your own key. Your '
        'questions, and the numbers it looks up to answer them, go straight '
        'to that provider and nowhere else. A model on your own network '
        'keeps them at home. A web search sends only the search words.',
  ),
  (
    LucideIcons.users,
    'Community is opt-in',
    'Nothing is shared unless you sign in to the community. You choose which '
        'daily scores your teams see: recovery, strain or sleep time. Untick '
        'one and what was already shared is removed too.',
  ),
  (
    LucideIcons.bug,
    'Crash reports are off until you say so',
    'When they are on, a report holds the error and where in the app it '
        'happened, not your health data.',
  ),
  (
    LucideIcons.downloadCloud,
    'Update checks',
    'Looking for a new version asks GitHub for the latest release, which '
        'sees your IP address. Turn it off under About.',
  ),
  (
    LucideIcons.hardDriveDownload,
    'Yours to take or delete',
    'Export everything at any time from Data export, or delete it all from '
        'the foot of More.',
  ),
];
