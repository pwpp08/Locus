// The journal page's bell: a daily reminder at a time you pick, and a one-off
// "ask me again later".

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../notify/notification_center.dart';
import '../../notify/notification_prefs.dart';
import '../../state/app_state.dart';
import '../ui2.dart';

Future<void> showJournalReminderSheet(BuildContext c) async {
  final prefs = await NotificationPrefs.load();
  if (!c.mounted) return;
  await AppSheet.open<void>(
    c,
    scroll: true,
    builder: (_) => _Sheet(prefs: prefs, app: c.read<AppState>()),
  );
}

class _Sheet extends StatefulWidget {
  final NotificationPrefs prefs;
  final AppState app;
  const _Sheet({required this.prefs, required this.app});

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  late NotificationPrefs _prefs = widget.prefs;
  String? _note;

  static const _defaultMin = 21 * 60;

  int get _minute => _prefs.checkInAtMin ?? _defaultMin;

  String _clock(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _save(NotificationPrefs next) async {
    setState(() => _prefs = next);
    await next.save();
    if (next.checkInEnabled) {
      await NotificationCenter.instance.askForPermission();
    }
    await widget.app.refreshAiReminders();
  }

  Future<void> _pickDaily() async {
    final t = await pickTime(
      context,
      initial: TimeOfDay(hour: _minute ~/ 60, minute: _minute % 60),
      title: 'Remind me at',
    );
    if (t == null || !mounted) return;
    await _save(
      _prefs.copyWith(
        checkInEnabled: true,
        checkInAtMin: t.hour * 60 + t.minute,
      ),
    );
  }

  Future<void> _later(DateTime at) async {
    final ok = await NotificationCenter.instance.remindJournalAt(at);
    if (!mounted) return;
    setState(
      () => _note = ok
          ? 'I will remind you at ${_clock(at.hour * 60 + at.minute)}.'
          : 'Notifications are off for this app, so that cannot be set.',
    );
  }

  Future<void> _pickLater() async {
    final now = TimeOfDay.now();
    final t = await pickTime(context, initial: now, title: 'Remind me at');
    if (t == null) return;
    final n = DateTime.now();
    var at = DateTime(n.year, n.month, n.day, t.hour, t.minute);
    if (!at.isAfter(n)) at = DateTime(n.year, n.month, n.day + 1, t.hour, t.minute);
    await _later(at);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget option(String label, VoidCallback onTap) => Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: S.x3,
          vertical: S.x2,
        ),
        decoration: BoxDecoration(
          color: p.ink.withValues(alpha: .08),
          borderRadius: R.rPill,
        ),
        child: Text(label, style: F.cap.copyWith(color: p.ink)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x5, S.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Journal reminders', style: F.head.copyWith(color: p.ink)),
          const SizedBox(height: S.x4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Remind me every day',
                  style: F.body.copyWith(color: p.ink),
                ),
              ),
              AppSwitch(
                _prefs.checkInEnabled,
                (v) => _save(_prefs.copyWith(checkInEnabled: v)),
                semanticLabel: 'Daily journal reminder',
              ),
            ],
          ),
          if (_prefs.checkInEnabled) ...[
            const SizedBox(height: S.x2),
            Pressable(
              semanticLabel: 'Reminder time',
              onTap: _pickDaily,
              child: SizedBox(
                height: S.x10,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Time',
                        style: F.body.copyWith(color: p.ink2),
                      ),
                    ),
                    Text(
                      _prefs.checkInAtMin == null
                          ? 'Before bed'
                          : _clock(_minute),
                      style: F.body.copyWith(color: p.ink),
                    ),
                    const SizedBox(width: S.x1),
                    Icon(
                      LucideIcons.chevronRight,
                      size: I.sm,
                      color: p.ink3,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: S.x5),
          Text('Remind me later', style: F.body.copyWith(color: p.ink)),
          const SizedBox(height: S.x2),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              option(
                '30 min',
                () => _later(DateTime.now().add(const Duration(minutes: 30))),
              ),
              option(
                '1 hour',
                () => _later(DateTime.now().add(const Duration(hours: 1))),
              ),
              option(
                '2 hours',
                () => _later(DateTime.now().add(const Duration(hours: 2))),
              ),
              option('Pick a time', _pickLater),
            ],
          ),
          if (_note case final note?) ...[
            const SizedBox(height: S.x3),
            Text(note, style: F.cap.copyWith(color: p.ink2)),
          ],
        ],
      ),
    );
  }
}
