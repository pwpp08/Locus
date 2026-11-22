// BAND NOTIFICATIONS — buzz the strap when a phone app notifies you.
// ANDROID ONLY, and silently absent everywhere else: iOS has no API to observe
// another app's notifications, so there is no "unavailable on this device"
// copy to write.
//
// WHY THIS FILE HAD TO COME BACK. The relay itself never stopped working:
// `AppState` still bootstraps it, and the manifest still declares
// BIND_NOTIFICATION_LISTENER_SERVICE for it. What the UI rebuild deleted was
// every control — so the app shipped a notification-listener permission with
// no way to reach the feature it exists for. A permission a reviewer can read
// in the manifest and a user cannot find in the app is the problem, more than
// the missing feature is.
//
// WHERE THE APP LIST COMES FROM. Apps that have actually posted a notification
// while the listener was running, not the installed set. Enumerating installed
// packages needs QUERY_ALL_PACKAGES, which the sweep removed from the manifest
// with `tools:node="remove"` and called the most policy-expensive permission
// there is — that decision stands. It also happens to be the better list: the
// dozen apps that interrupt you, rather than two hundred to scroll past. The
// cost is that the list starts empty and fills over the first minutes, which
// the empty state says in as many words rather than looking broken.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ble/android_background.dart';
import '../../l10n/app_localizations.dart';
import '../../notify/notification_relay.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'profile.dart' show SetRow, settingsGroup;

/// One row's worth of the picker.
class RelayApp {
  const RelayApp(this.package, {this.icon, this.on = false, this.label});
  final String package;
  final Uint8List? icon;
  final bool on;

  /// The app's own name; guessed from [package] when not known.
  final String? label;
  String get name => label ?? appLabel(package);
}

/// The route. Reads the live [NotificationRelay] off [AppState] and hands
/// [BandNotificationsView] plain values — the view is what the tests pump, and
/// it never asks the platform anything.
class BandNotifications extends StatefulWidget {
  const BandNotifications({super.key});

  @override
  State<BandNotifications> createState() => _BandNotificationsState();
}

class _BandNotificationsState extends State<BandNotifications>
    with WidgetsBindingObserver {
  NotificationRelay get _relay => context.read<AppState>().notificationRelay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Every app on the launcher, by its own name, for the picker.
    _relay.loadLauncherApps(AndroidBackground.launcherApps);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the system Notification-access page: re-read the real grant
    // rather than trusting what the user said they did.
    if (state == AppLifecycleState.resumed && mounted) {
      _relay.refreshPermission();
    }
  }

  @override
  Widget build(BuildContext c) {
    final relay = _relay;
    return AnimatedBuilder(
      animation: relay,
      builder: (c, _) => BandNotificationsView(
        supported: relay.supported,
        enabled: relay.enabled,
        granted: relay.permissionGranted,
        apps: [
          for (final p in relay.pickerPackages)
            RelayApp(p,
                icon: relay.iconFor(p),
                on: relay.isAppEnabled(p),
                label: relay.labelFor(p)),
        ],
        callsOn: relay.callsEnabled,
        tasksOn: relay.tasksEnabled,
        onCalls: relay.setCallsEnabled,
        onTasks: relay.setTasksEnabled,
        onEnabled: relay.setEnabled,
        onGrant: relay.requestPermission,
        onApp: relay.setAppEnabled,
      ),
    );
  }
}

/// The screen, as a pure function of its inputs.
class BandNotificationsView extends StatelessWidget {
  const BandNotificationsView({
    super.key,
    this.supported = true,
    this.enabled = false,
    this.granted = false,
    this.apps = const [],
    this.callsOn = true,
    this.tasksOn = true,
    this.onCalls,
    this.onTasks,
    this.onEnabled,
    this.onGrant,
    this.onApp,
  });

  final bool supported, enabled, granted, callsOn, tasksOn;
  final ValueChanged<bool>? onCalls, onTasks;
  final List<RelayApp> apps;
  final ValueChanged<bool>? onEnabled;
  final VoidCallback? onGrant;
  final void Function(String pkg, bool on)? onApp;

  /// How many apps are actually armed — the one number that says whether the
  /// feature will do anything at all.
  int get _armed => apps.where((a) => a.on).length;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(l?.bandNotifNavTitle ?? 'Band notifications',
                sub: l?.bandNotifNavSub ?? 'WHAT MAKES THE STRAP BUZZ'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                if (!supported)
                  StatusCard(
                    l?.bandNotifUnsupportedTitle ?? 'This phone cannot do it',
                    l?.bandNotifUnsupportedBody ??
                        'Reading which app posted a notification is an Android '
                            'capability. iOS gives no app that access, including '
                            'this one.',
                    icon: LucideIcons.smartphone,
                  )
                else ...[
                  settingsGroup(c, l?.bandNotifRelayGroup ?? 'Relay', [
                    SetRow(LucideIcons.bellRing, C.dialStrain,
                        l?.bandNotifBuzzOnAppNotifs ??
                            'Buzz on app notifications',
                        // What is actually true, and no more. The relay reads
                        // no content and sends nothing anywhere — but it DOES
                        // keep the package names on this phone, because that
                        // list is the only way the picker below can offer you
                        // an app without asking for the permission that
                        // enumerates every app you have installed. "Nothing is
                        // stored" was the wrong claim to make about it.
                        sub: l?.bandNotifBuzzSub ??
                            'The strap buzzes when an app below notifies you. Only the app’s name is kept, on this phone; what a notification says is never read',
                        switchValue: enabled,
                        onTap: () => onEnabled?.call(!enabled)),
                    if (enabled && granted)
                      SetRow(LucideIcons.listChecks, C.stressLow,
                          l?.bandNotifAppsArmed ?? 'Apps armed',
                          value: '$_armed', chevron: false),
                  ]),
                  if (enabled && !granted) ...[
                    const SizedBox(height: S.x4),
                    StatusCard(
                      l?.bandNotifPermissionTitle ??
                          'Android needs to let us see notifications',
                      l?.bandNotifPermissionBody ??
                          'The permission says which app posted, and that is all '
                              'this uses it for. The names stay on this phone and '
                              'nothing leaves it.',
                      fix: l?.bandNotifGrantAccess ?? 'Grant notification access',
                      icon: LucideIcons.shieldCheck,
                      onFix: onGrant,
                    ),
                  ],
                  if (enabled && granted) ...[
                    const SizedBox(height: S.x4),
                    // Two moments with a buzz of their own, which need no app
                    // picked below: a call is three long buzzes, a Google Tasks
                    // reminder two short ones.
                    settingsGroup(c, 'Patterns', [
                      SetRow(LucideIcons.phoneIncoming, C.optimal, 'Incoming calls',
                          sub: 'Three long buzzes while it rings',
                          switchValue: callsOn,
                          onTap: () => onCalls?.call(!callsOn)),
                      SetRow(LucideIcons.listChecks, C.dialStrain, 'Google Tasks',
                          sub: 'Two short buzzes for a reminder',
                          switchValue: tasksOn,
                          onTap: () => onTasks?.call(!tasksOn)),
                    ]),
                    const SizedBox(height: S.x4),
                    if (apps.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: S.x4),
                        child: StatusCard(
                          l?.bandNotifEmptyTitle ?? 'No app has notified you yet',
                          // Absence with its reason, not an empty list: this
                          // is the cost of not asking for the permission that
                          // enumerates every installed app, and it resolves
                          // itself within minutes of ordinary use.
                          l?.bandNotifEmptyBody ??
                              'Apps appear here the first time each one notifies you while the relay is on. From its second notification, an app can buzz.',
                          icon: LucideIcons.hourglass,
                        ),
                      )
                    else
                      _AppPicker(apps, onApp: onApp),
                  ],
                  const SizedBox(height: S.x4),
                  StatusCard(
                    l?.bandNotifOneBuzzTitle ?? 'One buzz, not a stream',
                    l?.bandNotifOneBuzzBody ??
                        'Repeats from one app within four seconds are ignored. Ongoing notifications (music, downloads) never buzz, and nothing buzzes while disconnected.',
                    icon: LucideIcons.waves,
                  ),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// The apps, with a search over them: the ones that buzz first, then the
/// rest by name, each a row with its icon, its own name and a switch.
class _AppPicker extends StatefulWidget {
  const _AppPicker(this.apps, {this.onApp});
  final List<RelayApp> apps;
  final void Function(String pkg, bool on)? onApp;

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  String _q = '';

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final a in widget.apps)
        if (q.isEmpty ||
            a.name.toLowerCase().contains(q) ||
            a.package.toLowerCase().contains(q))
          a,
    ]..sort((a, b) => a.on != b.on
        ? (a.on ? -1 : 1)
        : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: S.tap,
        padding: const EdgeInsets.symmetric(horizontal: S.x3),
        decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
        child: Row(children: [
          Icon(LucideIcons.search, size: I.md, color: p.ink3),
          const SizedBox(width: S.x2),
          Expanded(
            child: AppField(
              bare: true,
              hint: 'Search apps',
              semanticLabel: 'Search apps',
              autocorrect: false,
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
        ]),
      ),
      const SizedBox(height: S.x3),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x4),
          child: Text('No app matches "$_q".',
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.ink3)),
        )
      else
        Container(
          decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
          padding: const EdgeInsets.symmetric(horizontal: S.x3),
          child: Column(children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) Container(height: S.hair, color: p.line),
              _AppRow(shown[i], onChanged: widget.onApp),
            ],
          ]),
        ),
    ]);
  }
}

/// One app: its icon, its own name, and whether it buzzes.
class _AppRow extends StatelessWidget {
  const _AppRow(this.app, {this.onChanged});
  final RelayApp app;
  final void Function(String pkg, bool on)? onChanged;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final icon = app.icon;
    // Decoded at the size it is drawn at: launcher masters run up to 512 px.
    // WIDTH ONLY, as a third-party icon need not be square.
    final px = (S.x8 * MediaQuery.devicePixelRatioOf(c)).round();
    final l = AppLocalizations.of(c);
    return Pressable(
      onTap: () => onChanged?.call(app.package, !app.on),
      semanticLabel: '${app.name}, ${app.on ? (l?.bandNotifBuzzesDescription ?? 'buzzes') : (l?.bandNotifDoesNotBuzzDescription ?? 'does not buzz')}',
      child: SizedBox(
        height: S.tap + S.x2,
        child: Row(children: [
          ClipRRect(
            borderRadius: R.rSm,
            child: icon != null && icon.isNotEmpty
                ? Image.memory(icon,
                    width: S.x8,
                    height: S.x8,
                    cacheWidth: px,
                    gaplessPlayback: true)
                : Container(
                    width: S.x8,
                    height: S.x8,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: p.wash(C.dialStrain), borderRadius: R.rSm),
                    child: Icon(LucideIcons.appWindow,
                        size: I.sm, color: p.on(C.dialStrain)),
                  ),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(app.name,
                style: F.body.copyWith(color: p.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: S.x2),
          ExcludeSemantics(
            child: AppSwitch(
              app.on,
              (v) => onChanged?.call(app.package, v),
              semanticLabel: app.name,
            ),
          ),
        ]),
      ),
    );
  }
}
