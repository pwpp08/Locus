// update_dialog.dart — the sheet that offers a new build and installs it.
//
// "Update now" downloads the APK inside the app and opens Android's installer;
// the phone asks for its usual confirmation, and the new build deletes the
// download when it starts. Where that cannot work (the install permission
// refused, no network) the sheet says why and offers the browser instead.
//
// It is a dial-screen sheet: the slate gradient, the grab bar, the title in
// tracked capitals. Under the Locus mark, the new build in large type; a card
// with what is installed, what is new and the download's size, values flush
// right; what changed, from the release notes; then the actions.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../updater/update_service.dart';
import '../grammar.dart';
import '../logo.dart';
import '../profile/devices.dart' show formatDayTime;
import '../lucide.dart';
import '../screens/dial_parts.dart' show dialCard, kDialMargin, kDialPad;
import '../theme.dart';

class UpdateDialog extends StatefulWidget {
  final ReleaseInfo release;

  const UpdateDialog({super.key, required this.release});

  static Future<void> show(BuildContext context,
          {required ReleaseInfo release}) =>
      AppSheet.open<void>(
        context,
        scroll: true,
        bare: true,
        builder: (_) => UpdateDialog(release: release),
      );

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  StreamSubscription<UpdateProgress>? _sub;
  UpdateProgress? _progress;

  bool get _busy => _progress != null && _progress!.phase != 'error';

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

  void _later(BuildContext c) {
    UpdateService.instance.decline(widget.release);
    Navigator.of(c).pop();
  }

  @override
  Widget build(BuildContext c) {
    final r = widget.release;
    final svc = UpdateService.instance;
    final prog = _progress;
    final failed = prog?.phase == 'error';
    final canInstall = r.apkUrl != null;
    final notes = r.whatsNew;
    final published = r.publishedAt?.toLocal();
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .92),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [DC.sheetTop, DC.sheetFoot],
        ),
      ),
      padding: EdgeInsets.fromLTRB(kDialMargin, S.x4 + S.half + S.hair,
          kDialMargin, S.x5 + MediaQuery.paddingOf(c).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: S.x16 + S.x2,
              height: S.x1 + S.hair,
              decoration:
                  const BoxDecoration(color: DC.grab, borderRadius: R.rPill),
            ),
          ),
          const SizedBox(height: S.x6),
          const Center(child: LocusMark(size: S.x12)),
          const SizedBox(height: S.x4),
          Semantics(
            header: true,
            child: Text('UPDATE AVAILABLE',
                textAlign: TextAlign.center,
                style: F.dLabel.copyWith(color: DC.ink2)),
          ),
          const SizedBox(height: S.x2),
          Text(r.label,
              textAlign: TextAlign.center,
              style: F.dHead.copyWith(color: DC.ink)),
          const SizedBox(height: S.x6),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: kDialPad),
                    decoration: dialCard(),
                    child: Column(children: [
                      _Row('Installed',
                          svc.currentBuild.isEmpty ? '--' : svc.currentBuild),
                      _Row('New', r.label, tone: C.optimal),
                      if (published != null)
                        _Row('Published',
                            formatDayTime(published, AppLocalizations.of(c))),
                      if (r.formattedSize.isNotEmpty)
                        _Row('Download', r.formattedSize, last: true),
                    ]),
                  ),
                  if (notes.isNotEmpty && !_busy) ...[
                    const SizedBox(height: S.x3),
                    Container(
                      padding: const EdgeInsets.all(kDialPad),
                      decoration: dialCard(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WHAT’S NEW',
                              style: F.dLabel.copyWith(color: DC.ink)),
                          const SizedBox(height: S.x3),
                          Text(notes,
                              style: F.dText
                                  .copyWith(color: DC.body, height: 1.45)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: S.x6),
          if (_busy) ...[
            _Bar(
                value: prog!.phase == 'installing' ? 1 : prog.percent / 100),
            const SizedBox(height: S.x3),
            Text(
              prog.phase == 'installing'
                  ? 'OPENING THE INSTALLER'
                  : 'DOWNLOADING ${prog.percent}%',
              textAlign: TextAlign.center,
              style: F.dLabel.copyWith(color: DC.ink2),
            ),
          ] else ...[
            if (failed) ...[
              Text(prog!.message ?? 'The update did not install.',
                  textAlign: TextAlign.center,
                  style: F.dText.copyWith(color: C.strainDown, height: 1.4)),
              const SizedBox(height: S.x4),
            ],
            if (canInstall)
              BigButton(
                failed ? 'Try again' : 'Update now',
                icon: failed ? LucideIcons.refreshCw : LucideIcons.download,
                onTap: _start,
              ),
            if (failed || !canInstall) ...[
              const SizedBox(height: S.x3),
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
            const SizedBox(height: S.x3),
            BigButton('Later', soft: true, onTap: () => _later(c)),
          ],
        ],
      ),
    );
  }
}

/// A row of the version card: the name in tracked capitals on the left, the
/// value flush right.
class _Row extends StatelessWidget {
  final String label, value;
  final Color tone;
  final bool last;
  const _Row(this.label, this.value, {this.tone = DC.ink, this.last = false});

  @override
  Widget build(BuildContext c) => Container(
        constraints: const BoxConstraints(minHeight: S.x12),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: DC.line, width: S.hair)),
        ),
        child: Row(children: [
          Text(label.toUpperCase(), style: F.dLabel.copyWith(color: DC.ink2)),
          const SizedBox(width: S.x4),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: F.dText.copyWith(color: tone, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

/// A slim bar: the share done in the strain blue over the dials' track.
class _Bar extends StatelessWidget {
  final double value;
  const _Bar({required this.value});

  @override
  Widget build(BuildContext c) => ClipRRect(
        borderRadius: R.rPill,
        child: SizedBox(
          height: S.x1 + S.half,
          child: Stack(children: [
            const Positioned.fill(child: ColoredBox(color: DC.track)),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: const ColoredBox(color: C.dialStrain),
            ),
          ]),
        ),
      );
}
