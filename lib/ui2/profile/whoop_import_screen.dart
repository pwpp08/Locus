// Bringing a WHOOP "My Data" export in: where to get it, then the same import
// every other file goes through.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../onboarding/welcome.dart'
    show ImportOutcome, PassphraseCancelled, askBackupPassphrase, runImport;
import '../ui2.dart';

class WhoopImportScreen extends StatefulWidget {
  const WhoopImportScreen({super.key});

  @override
  State<WhoopImportScreen> createState() => _WhoopImportScreenState();
}

class _WhoopImportScreenState extends State<WhoopImportScreen> {
  bool _busy = false;
  ImportOutcome? _done;
  String? _error;

  Future<void> _pick() async {
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _done = null;
      _error = null;
    });
    try {
      final picked = await FilePicker.platform
          .pickFiles(allowMultiple: true, withReadStream: false);
      final paths = (picked?.files ?? const [])
          .map((f) => f.path)
          .whereType<String>()
          .toList();
      if (paths.isEmpty || !mounted) return;
      final outcome = await runImport(
        app,
        paths,
        askPassphrase: () => askBackupPassphrase(context),
      );
      if (mounted) setState(() => _done = outcome);
    } on PassphraseCancelled {
      // They closed the prompt: nothing to report.
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'That file could not be read as an export. $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget step(String n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: S.x6,
            child: Text(n, style: F.num(F.body).copyWith(color: p.ink3)),
          ),
          Expanded(child: Text(text, style: F.body.copyWith(color: p.ink))),
        ],
      ),
    );
    final done = _done;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar('Import WHOOP data'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x10),
                children: [
                  Surface(
                    pad: const EdgeInsets.all(S.x4),
                    child: Column(
                      children: [
                        step('1', 'In the WHOOP app, open More, then App '
                            'Settings, then Data Export.'),
                        step('2', 'Ask for your data. They email you a link '
                            'to a zip file.'),
                        step('3', 'Save the zip to your phone and choose it '
                            'below. The zip itself is fine, or the CSV files '
                            'inside it.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: S.x3),
                  Text(
                    'Days this band has already measured are left alone. '
                    'An export only holds daily scores and workouts, so '
                    'imported days have no second-by-second charts.',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                  const SizedBox(height: S.x5),
                  BigButton(
                    _busy ? 'Importing…' : 'Choose file',
                    busy: _busy,
                    onTap: _busy ? null : _pick,
                  ),
                  if (done != null) ...[
                    const SizedBox(height: S.x4),
                    Text(
                      done.error ??
                          done.readError ??
                          (done.days == 0 && done.workouts == 0
                              ? 'Nothing new was found in that file.'
                              : '${done.days} days and ${done.workouts} '
                                  'workouts imported'
                                  '${done.skippedDays > 0 ? ', ${done.skippedDays} days already measured were left alone' : ''}.'),
                      style: F.body.copyWith(color: p.ink2),
                    ),
                  ],
                  if (_error case final e?) ...[
                    const SizedBox(height: S.x4),
                    Text(e, style: F.body.copyWith(color: p.ink2)),
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
