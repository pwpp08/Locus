// update_dialog.dart — in-app dialog/sheet presenting available GitHub release updates.

import 'package:flutter/material.dart';

import '../../updater/update_service.dart';
import '../ui2.dart';

class UpdateDialog extends StatelessWidget {
  final ReleaseInfo release;
  final String currentVersion;

  const UpdateDialog({
    super.key,
    required this.release,
    required this.currentVersion,
  });

  static Future<void> show(
    BuildContext context, {
    required ReleaseInfo release,
    required String currentVersion,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => UpdateDialog(
        release: release,
        currentVersion: currentVersion,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final sizeText = release.formattedSize;

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x6),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: S.x4),
                decoration: BoxDecoration(
                  color: p.ink3.withValues(alpha: 0.3),
                  borderRadius: R.rPill,
                ),
              ),
            ),

            // Header Icon & Title
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: p.wash(C.blue),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.sparkles, color: C.blue, size: 22),
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New Update Available',
                        style: F.t2.copyWith(color: p.ink),
                      ),
                      Text(
                        'v$currentVersion  ➔  ${release.tagName}',
                        style: F.cap.copyWith(
                          color: C.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.x4),

            // Release title & size
            if (release.title.isNotEmpty) ...[
              Text(
                release.title,
                style: F.body.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: S.x1),
            ],

            if (sizeText.isNotEmpty) ...[
              Row(
                children: [
                  Icon(LucideIcons.hardDrive, size: 14, color: p.ink3),
                  const SizedBox(width: S.x1),
                  Text(
                    'Download package: $sizeText',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                ],
              ),
              const SizedBox(height: S.x2),
            ],

            // Changelog / Notes
            if (release.body.trim().isNotEmpty) ...[
              Text(
                'Release Notes:',
                style: F.cap.copyWith(
                  color: p.ink3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: S.x1),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(S.x3),
                decoration: BoxDecoration(
                  color: p.card2,
                  borderRadius: R.rMd,
                ),
                child: SingleChildScrollView(
                  child: Text(
                    release.body.trim(),
                    style: F.cap.copyWith(color: p.ink),
                  ),
                ),
              ),
              const SizedBox(height: S.x4),
            ],

            // Action Buttons
            BigButton(
              release.apkUrl != null ? 'Download APK Update' : 'View on GitHub',
              icon: LucideIcons.download,
              color: C.blue,
              onTap: () {
                UpdateService.startDownload(release);
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: S.x2),

            Center(
              child: TextAction('Later', () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }
}
