// The Macros tab's own camera: a live preview in a sheet and one shutter, so
// logging food never hands the phone over to the system camera app.
//
// The shutter takes a still and the app decides what it is. A product barcode
// in the picture becomes a barcode lookup; anything else is a photo of a plate
// or a label for the AI estimate. The button on the right opens the live
// barcode scanner for the times a still is not enough (a small or curved code),
// and the one on the left picks a picture that is already in the gallery, which
// goes through the same decision.
//
// Nothing is kept. The still is read on the device, shrunk, and its file is
// deleted; only a photo that is going to the AI leaves the sheet, as bytes.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../scan/barcode_reader.dart';
import '../ui2.dart';
import 'scan_barcode.dart' show kProductFormats;

/// What the camera sheet saw.
enum FoodShotKind { barcode, photo, scan }

class FoodShot {
  const FoodShot.barcode(String this.code)
      : kind = FoodShotKind.barcode,
        photo = null;
  const FoodShot.photo(Uint8List this.photo)
      : kind = FoodShotKind.photo,
        code = null;

  /// The person wants the live scanner; the caller opens it.
  const FoodShot.scan()
      : kind = FoodShotKind.scan,
        code = null,
        photo = null;

  final FoodShotKind kind;
  final String? code;
  final Uint8List? photo;
}

/// The longest side a photo keeps before it is sent anywhere, and the JPEG
/// quality: about 100 KB, so three fit the Coach's request ceiling.
const kFoodPhotoEdge = 1024;
const kFoodPhotoQuality = 70;

/// A camera still (several MB, rotated by EXIF) as a small upright JPEG. Pure
/// and top-level so it can run in an isolate.
Uint8List shrinkPhoto(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return bytes;
  }
  if (decoded == null) return bytes;
  var im = img.bakeOrientation(decoded);
  final long = im.width > im.height ? im.width : im.height;
  if (long > kFoodPhotoEdge) {
    im = im.width >= im.height
        ? img.copyResize(im, width: kFoodPhotoEdge)
        : img.copyResize(im, height: kFoodPhotoEdge);
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: kFoodPhotoQuality));
}

/// The cameras the device has. A seam so a test can answer "none".
@visibleForTesting
Future<List<CameraDescription>> Function() foodCameraList = availableCameras;

/// Opens the camera. Resolves what it saw, or null when it was closed.
/// [barcodes] false is for a place that only wants a photo (the AI sheet):
/// the shutter then never looks for a code and there is no scan button.
Future<FoodShot?> openFoodCamera(BuildContext c, {bool barcodes = true}) =>
    AppSheet.open<FoodShot>(
      c,
      scroll: true,
      builder: (_) => _FoodCameraSheet(barcodes: barcodes),
    );

class _FoodCameraSheet extends StatefulWidget {
  const _FoodCameraSheet({required this.barcodes});
  final bool barcodes;

  @override
  State<_FoodCameraSheet> createState() => _FoodCameraSheetState();
}

class _FoodCameraSheetState extends State<_FoodCameraSheet>
    with WidgetsBindingObserver {
  CameraController? _cam;

  /// Set when the camera could not start; [_denied] says why.
  bool _failed = false;
  bool _denied = false;
  bool _busy = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    super.dispose();
  }

  /// A camera held while the app is in the background is a camera nobody else
  /// can open, so it is let go and taken again on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
      final cam = _cam;
      _cam = null;
      cam?.dispose();
      if (mounted) setState(() {});
    } else if (s == AppLifecycleState.resumed && _cam == null && !_failed) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      final cams = await foodCameraList();
      if (cams.isEmpty) throw StateError('no camera');
      final back = cams.where((d) => d.lensDirection == CameraLensDirection.back);
      final cam = CameraController(
        back.isNotEmpty ? back.first : cams.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await cam.initialize();
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() => _cam = cam);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _denied = e.code.startsWith('CameraAccessDenied') ||
              e.code == 'CameraAccessRestricted';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _shoot() async {
    final cam = _cam;
    if (cam == null || _busy || !cam.value.isInitialized) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    HapticFeedback.lightImpact();
    try {
      final shot = await cam.takePicture();
      await _decide(shot.path, delete: true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _note = 'That did not work. Try again.';
        });
      }
    }
  }

  Future<void> _gallery() async {
    if (_busy) return;
    try {
      final f = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: kFoodPhotoEdge.toDouble(),
          maxHeight: kFoodPhotoEdge.toDouble(),
          imageQuality: kFoodPhotoQuality);
      if (f == null || !mounted) return;
      setState(() => _busy = true);
      await _decide(f.path);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _note = 'The gallery could not be opened.';
        });
      }
    }
  }

  /// A product barcode in the picture is a barcode; anything else is a photo.
  Future<void> _decide(String path, {bool delete = false}) async {
    final code = widget.barcodes
        ? await readBarcodeInImage(path, kProductFormats)
        : null;
    FoodShot? out;
    if (code != null) {
      out = FoodShot.barcode(code);
    } else {
      final bytes = await File(path).readAsBytes();
      out = FoodShot.photo(await compute(shrinkPhoto, bytes));
    }
    if (delete) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return SizedBox(
      height: MediaQuery.sizeOf(c).height * .9,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            S.x5, S.x5, S.x5, S.x5 + MediaQuery.paddingOf(c).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Log with the camera',
                      style: F.t2.copyWith(color: p.ink)),
                ),
                Pressable(
                  semanticLabel: 'Close',
                  onTap: () => Navigator.of(c).pop(),
                  child: Icon(LucideIcons.x, size: I.md, color: p.ink3),
                ),
              ],
            ),
            const SizedBox(height: S.x1),
            Text(
              widget.barcodes
                  ? 'Point it at a plate or a barcode. The shutter reads either.'
                  : 'Photograph the plate or the label.',
              style: F.cap.copyWith(color: p.ink3),
            ),
            const SizedBox(height: S.x4),
            Expanded(
              child: ClipRRect(
                borderRadius: R.rXl,
                child: ColoredBox(color: C.n900, child: _preview(c, p)),
              ),
            ),
            if (_note != null) ...[
              const SizedBox(height: S.x3),
              ErrorLine(_note!),
            ],
            const SizedBox(height: S.x5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SideButton(LucideIcons.image, 'Choose from the gallery', _gallery),
                _Shutter(busy: _busy, onTap: _cam == null ? null : _shoot),
                widget.barcodes
                    ? _SideButton(LucideIcons.scanBarcode, 'Scan a barcode live',
                        () => Navigator.of(c).pop(const FoodShot.scan()))
                    : const SizedBox.square(dimension: S.x12 + S.x2),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext c, P p) {
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(S.x4),
          child: StatusCard(
            _denied ? 'No camera access' : 'The camera did not start',
            _denied
                ? 'Logging with the camera needs it, and this app has not been '
                    'given it.'
                : 'This device would not open its camera.',
            fix: 'Choose from the gallery',
            icon: LucideIcons.cameraOff,
            onFix: _gallery,
          ),
        ),
      );
    }
    final cam = _cam;
    final size = cam?.value.previewSize;
    if (cam == null || size == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    // The preview reports its size sideways (landscape); the phone is upright.
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.height,
        height: size.width,
        child: CameraPreview(cam),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        width: S.x12 + S.x2,
        height: S.x12 + S.x2,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.card2),
        child: Icon(icon, size: I.lg, color: p.ink),
      ),
    );
  }
}

/// The white ring with a white disc in it.
class _Shutter extends StatelessWidget {
  const _Shutter({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      semanticLabel: 'Take a picture',
      onTap: busy ? null : onTap,
      child: Container(
        width: S.x16 + S.x2 * 2,
        height: S.x16 + S.x2 * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.ink, width: S.x1 - S.hair),
        ),
        child: Container(
          width: S.x16 - S.x1,
          height: S.x16 - S.x1,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: p.ink),
          child: busy
              ? SizedBox.square(
                  dimension: I.md,
                  child: CircularProgressIndicator(strokeWidth: 2, color: p.bg))
              : null,
        ),
      ),
    );
  }
}
