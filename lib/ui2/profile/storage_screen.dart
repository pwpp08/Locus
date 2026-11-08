// What the database on this phone is made of, and a way to hand back the
// space it is no longer using.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../compute/derivation_engine.dart' show rawRetentionDays;
import '../../data/db.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'profile.dart' show formatBytes;

/// One line of the breakdown.
typedef StorageLine = ({String label, String sub, int bytes});

/// The tables, grouped under what they mean to a person, largest first. What
/// the tables do not account for is the database's own indexes.
List<StorageLine> storageLines({
  required List<Map<String, dynamic>> tables,
  required int fileBytes,
  required int freeBytes,
}) {
  const named = {
    'decoded_onehz': 'readings',
    'decoded_rr': 'beats',
    'raw_archive': 'undecoded',
  };
  final by = <String, int>{};
  for (final t in tables) {
    final bytes = (t['bytes'] as num?)?.toInt() ?? 0;
    final group = named[t['table']] ?? 'history';
    by[group] = (by[group] ?? 0) + bytes;
  }
  final counted = by.values.fold<int>(0, (a, b) => a + b) + freeBytes;
  final lines = <StorageLine>[
    (
      label: 'Second-by-second readings',
      sub: 'The last $rawRetentionDays days, then deleted',
      bytes: by['readings'] ?? 0,
    ),
    (
      label: 'Heartbeat intervals',
      sub: 'The last $rawRetentionDays days, then deleted',
      bytes: by['beats'] ?? 0,
    ),
    (
      label: 'Unreadable band data',
      sub: 'Kept so a later update can read it',
      bytes: by['undecoded'] ?? 0,
    ),
    (
      label: 'Scores and history',
      sub: 'Everything else, kept for good',
      bytes: by['history'] ?? 0,
    ),
    (
      label: 'Search indexes',
      sub: 'What makes the charts quick to open',
      bytes: fileBytes > counted ? fileBytes - counted : 0,
    ),
    (
      label: 'Empty space',
      sub: 'Left by deleted data, reused as new data arrives',
      bytes: freeBytes,
    ),
  ]..sort((a, b) => b.bytes.compareTo(a.bytes));
  return [for (final l in lines) if (l.bytes > 0) l];
}

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  List<StorageLine>? _lines;
  int _file = 0, _free = 0;
  bool _failed = false, _freeing = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tables = await LocalDb.tableStorageStats();
      final file = await LocalDb.databaseFileBytes();
      final free = await LocalDb.freelistBytes();
      if (!mounted) return;
      setState(() {
        _file = file;
        _free = free;
        _failed = false;
        _lines = storageLines(tables: tables, fileBytes: file, freeBytes: free);
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _freeUp() async {
    setState(() {
      _freeing = true;
      _note = null;
    });
    final app = context.read<AppState>();
    String note;
    try {
      final freed = await app.freeUpSpace();
      note = freed == null
          ? 'The app is syncing or recording right now. Try again in a moment.'
          : freed == 0
              ? 'There was nothing to free up.'
              : '${formatBytes(freed)} handed back to your phone.';
    } catch (_) {
      note = 'That needs some free space on your phone first. Nothing was '
          'changed.';
    }
    await _load();
    if (mounted) {
      setState(() {
        _freeing = false;
        _note = note;
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final lines = _lines;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar('Storage'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x10),
                children: [
                  if (_failed)
                    Text(
                      'Could not read the storage figures. Open this page again.',
                      style: F.body.copyWith(color: p.ink2),
                    )
                  else if (lines == null)
                    const Padding(
                      padding: EdgeInsets.only(top: S.x10),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    Text(
                      formatBytes(_file),
                      style: F.n48.copyWith(color: p.ink),
                    ),
                    const SizedBox(height: S.x1),
                    Text(
                      'on this phone',
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                    const SizedBox(height: S.x6),
                    Surface(
                      pad: const EdgeInsets.symmetric(
                        horizontal: S.x4,
                        vertical: S.x2,
                      ),
                      child: Column(
                        children: [
                          for (final l in lines)
                            _Line(l, _file <= 0 ? 0 : l.bytes / _file),
                        ],
                      ),
                    ),
                    const SizedBox(height: S.x5),
                    BigButton(
                      _freeing
                          ? 'Freeing up…'
                          : _free > 0
                              ? 'Free up ${formatBytes(_free)}'
                              : 'Free up space',
                      busy: _freeing,
                      onTap: _freeing || _free <= 0 ? null : _freeUp,
                    ),
                    if (_note case final note?) ...[
                      const SizedBox(height: S.x3),
                      Text(note, style: F.cap.copyWith(color: p.ink2)),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final StorageLine line;
  final double share;
  const _Line(this.line, this.share);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x2 + S.half),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(line.label, style: F.body.copyWith(color: p.ink)),
              ),
              const SizedBox(width: S.x3),
              Text(formatBytes(line.bytes), style: F.cap.copyWith(color: p.ink2)),
            ],
          ),
          Text(line.sub, style: F.cap.copyWith(color: p.ink3)),
          const SizedBox(height: S.x2),
          ClipRRect(
            borderRadius: R.rPill,
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: S.x1,
              backgroundColor: p.ink.withValues(alpha: .08),
              valueColor: AlwaysStoppedAnimation(C.dialSleep),
            ),
          ),
        ],
      ),
    );
  }
}
