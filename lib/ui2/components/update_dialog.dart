// update_dialog.dart — the sheet that offers a new build and installs it.
//
// "Update now" downloads the APK inside the app and opens Android's installer;
// the phone asks for its usual confirmation, and the new build deletes the
// download when it starts. Where that cannot work (the install permission
// refused, no network) the sheet says why and offers the browser instead.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../updater/update_service.dart';
import '../grammar.dart';
import '../lucide.dart';
import '../theme.dart';

class UpdateDialog extends StatefulWidget {
  final ReleaseInfo release;

  const UpdateDialog({super.key, required this.release});

  static Future<void> show(BuildContext context,
          {required ReleaseInfo release}) =>
      AppSheet.open<void>(
        context,
        scroll: true,
        builder: (_) => UpdateDialog(release: release),
      );

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  StreamSubscription<UpdateProgress>? _sub;
  UpdateProgress? _progress;

  bool get _busy =>
      _progress != null && _progress!.phase != 'error';

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    _sub?.cancel();
    setState(() => _progress = const UpdateProgress('downloading'));
    _sub = UpdateService.instance.install(widget.release).listen((e) {
      if (mounted) setState(() => _progress = e);
    });
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final r = widget.release;
    final svc = UpdateService.instance;
    final prog = _progress;
    final failed = prog?.phase == 'error';
    final canInstall = r.apkUrl != null;
    final notes = r.body.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(
          S.gutter, S.x3, S.gutter, S.x5 + MediaQuery.paddingOf(c).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: S.x10,
              height: S.x1,
              decoration: BoxDecoration(color: p.line, borderRadius: R.rPill),
            ),
          ),
          const SizedBox(height: S.x5),
          Row(
            children: [
              Container(
                width: S.x10 + S.x1,
                height: S.x10 + S.x1,
                decoration: BoxDecoration(
                    color: p.wash(C.dialStrain), shape: BoxShape.circle),
                child: Icon(LucideIcons.downloadCloud, size: I.md, color: p.on(C.dialStrain)),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Update available',
                          style: F.t2.copyWith(color: p.ink)),
                    ),
                    const SizedBox(height: S.x1),
                    Text(
                      '${svc.currentBuild.isEmpty ? 'This build' : svc.currentBuild}'
                      '  →  ${r.label}',
                      style: F.num(F.cap).copyWith(
                          color: p.on(C.dialStrain), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (r.formattedSize.isNotEmpty) ...[
            const SizedBox(height: S.x3),
            Row(
              children: [
                Icon(LucideIcons.hardDrive, size: I.sm, color: p.ink3),
                const SizedBox(width: S.x2),
                Text('Download: ${r.formattedSize}',
                    style: F.cap.copyWith(color: p.ink3)),
              ],
            ),
          ],
          if (notes.isNotEmpty && !_busy) ...[
            const SizedBox(height: S.x4),
            Text('WHAT’S IN IT', style: F.over.copyWith(color: p.ink3)),
            const SizedBox(height: S.x2),
            Container(
              constraints: const BoxConstraints(maxHeight: S.x16 * 3),
              padding: const EdgeInsets.all(S.x3),
              decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
              child: SingleChildScrollView(
                child: Text(notes, style: F.cap.copyWith(color: p.ink)),
              ),
            ),
          ],
          const SizedBox(height: S.x5),
          if (_busy) ...[
            _Bar(
              value: prog!.phase == 'installing' ? 1 : prog.percent / 100,
              color: p.fill(C.dialStrain),
              track: p.track,
            ),
            const SizedBox(height: S.x2),
            Text(
              prog.phase == 'installing'
                  ? 'Opening the installer…'
                  : 'Downloading ${prog.percent}%',
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.ink2),
            ),
          ] else ...[
            if (failed) ...[
              Text(prog!.message ?? 'The update did not install.',
                  style: F.cap.copyWith(color: p.on(C.strainDown), height: 1.4)),
              const SizedBox(height: S.x3),
            ],
            if (canInstall)
              BigButton(
                failed ? 'Try again' : 'Update now',
                icon: failed ? LucideIcons.refreshCw : LucideIcons.download,
                onTap: _start,
              ),
            if (failed || !canInstall) ...[
              const SizedBox(height: S.x2),
              BigButton(
                'Open in browser',
                icon: LucideIcons.externalLink,
                soft: canInstall,
                onTap: () {
                  UpdateService.startDownload(r);
                  Navigator.of(c).pop();
                },
              ),
            ],
            const SizedBox(height: S.x2),
            Center(
              child: TextAction('Later', () => Navigator.of(c).pop()),
            ),
          ],
        ],
      ),
    );
  }
}

/// A slim bar: the share done in [color] over [track].
class _Bar extends StatelessWidget {
  final double value;
  final Color color, track;
  const _Bar({required this.value, required this.color, required this.track});

  @override
  Widget build(BuildContext c) => ClipRRect(
        borderRadius: R.rPill,
        child: SizedBox(
          height: S.x2,
          child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: ColoredBox(color: color),
            ),
          ]),
        ),
      );
}
