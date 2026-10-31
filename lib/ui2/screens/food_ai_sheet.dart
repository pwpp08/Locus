// Logging food with the user's own AI: photos of the plate (or of a label), or
// a sentence about it. Two steps, never one:
//
//   1. CAPTURE — up to three photos and/or a note, sent to the provider the
//      Coach uses (ai/food_ai.dart). Without a key the sheet says where to add
//      one; nothing is sent anywhere.
//   2. REVIEW — every item the model proposed, its grams and its numbers. The
//      grams can be changed (every figure scales with them), an item renamed or
//      dropped, the meal chosen. Only what is confirmed here is logged, and it
//      is logged as a confirmed estimate ([FoodSource.photo] / [estimate]),
//      labelled "AI estimate" wherever it shows.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../ai/food_ai.dart';
import '../../coach/coach_config.dart';
import '../../coach/coach_engine.dart' show CoachException;
import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../data/nutrition_store.dart';
import '../ui2.dart';
import 'coach.dart' show CoachSetup, coachReadyNow;
import 'home_screen.dart' show go;
import 'journal_compose.dart' show OsTextField;

/// The most photos one estimate takes: each is downscaled to about 100 KB so
/// three fit the Coach's request ceiling with room for the reply.
const kFoodAiMaxPhotos = 3;

/// Opens the AI logger. [camera] starts on taking a photo, otherwise on the
/// description. Resolves true when something was logged.
Future<bool?> openFoodAi(BuildContext c,
    {required String date, String? meal, bool camera = false}) async {
  if (!coachReadyNow(c)) {
    return AppSheet.show<bool>(c,
        title: 'LOG WITH AI', child: const _NeedsKey());
  }
  final config = c.read<CoachConfig>();
  return AppSheet.open<bool>(c,
      scroll: true,
      builder: (_) => FoodAiSheet(
            config: config,
            date: date,
            meal: meal,
            camera: camera,
          ));
}

class _NeedsKey extends StatelessWidget {
  const _NeedsKey();

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.x5, 0, S.x5, S.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Photos and descriptions are read by your own AI provider, the one '
            'the Coach uses. Add a key and a model in AI coach settings; until '
            'then, scan a barcode or search your foods.',
            style: F.body.copyWith(color: p.ink2, height: 1.45),
          ),
          const SizedBox(height: S.x5),
          BigButton('Set up AI', onTap: () {
            Navigator.of(c).pop();
            go(c, const CoachSetup());
          }),
        ],
      ),
    );
  }
}

class FoodAiSheet extends StatefulWidget {
  final CoachConfig config;
  final String date;
  final String? meal;
  final bool camera;

  const FoodAiSheet({
    super.key,
    required this.config,
    required this.date,
    this.meal,
    this.camera = false,
  });

  @override
  State<FoodAiSheet> createState() => _FoodAiSheetState();
}

class _FoodAiSheetState extends State<FoodAiSheet> {
  final _note = TextEditingController();
  final _photos = <Uint8List>[];
  bool _busy = false;
  String? _error;

  /// The model's proposal once it has answered; null while capturing.
  List<FoodGuess>? _items;
  late String _meal = widget.meal ?? mealForHour(DateTime.now().hour);

  @override
  void initState() {
    super.initState();
    if (widget.camera) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _add(ImageSource.camera));
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _add(ImageSource from) async {
    final picker = ImagePicker();
    try {
      final room = kFoodAiMaxPhotos - _photos.length;
      if (room <= 0) return;
      final List<XFile> files;
      if (from == ImageSource.gallery && room > 1) {
        files = await picker.pickMultiImage(
            maxWidth: 1024, maxHeight: 1024, imageQuality: 70, limit: room);
      } else {
        final f = await picker.pickImage(
            source: from, maxWidth: 1024, maxHeight: 1024, imageQuality: 70);
        files = [?f];
      }
      final bytes = [for (final f in files.take(room)) await f.readAsBytes()];
      if (!mounted) return;
      setState(() => _photos.addAll(bytes));
    } catch (_) {
      if (mounted) setState(() => _error = 'The camera or gallery could not be opened.');
    }
  }

  Future<void> _analyze() async {
    if (_photos.isEmpty && _note.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = await analyzeFood(
          config: widget.config, text: _note.text, photos: _photos);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _items = items;
        if (items.isEmpty) {
          _error = 'No food recognised. Try another photo or a few words.';
          _items = null;
        }
      });
    } on CoachException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'The AI provider could not be reached. Try again.';
        });
      }
    }
  }

  Future<void> _log() async {
    final items = _items;
    if (items == null || items.isEmpty) return;
    setState(() => _busy = true);
    final db = await LocalDb.instance;
    final now = DateTime.now();
    final ts = widget.date == todayLabel()
        ? now.millisecondsSinceEpoch ~/ 1000
        : null;
    for (final g in items) {
      await NutritionDb.put(
        db,
        FoodEntry(
          id: NutritionDb.newId(),
          date: widget.date,
          meal: _meal,
          label: g.name,
          atTs: ts,
          quantity: g.grams,
          unit: 'g',
          kcal: g.kcal,
          proteinG: g.proteinG,
          carbsG: g.carbsG,
          fatG: g.fatG,
          fibreG: g.fibreG,
          sugarG: g.sugarG,
          satFatG: g.satFatG,
          sodiumMg: g.sodiumMg,
          source: _photos.isEmpty ? FoodSource.estimate : FoodSource.photo,
          // Reviewed on this sheet: the portion is the person's, so the
          // numbers may stand.
          confirmed: true,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final items = _items;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          S.x5, S.x5, S.x5, MediaQuery.of(c).viewInsets.bottom + S.x5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(items == null ? 'LOG WITH AI' : 'CHECK BEFORE LOGGING',
              style: F.caps.copyWith(color: p.ink)),
          const SizedBox(height: S.x1),
          Text(
            items == null
                ? 'Photograph the plate or the label, or say what you ate.'
                : 'An estimate. Set the grams to what you ate; the numbers follow.',
            style: F.cap.copyWith(color: p.ink3),
          ),
          const SizedBox(height: S.x4),
          if (items == null) ..._capture(c, p) else ..._review(c, p, items),
          if (_error != null) ...[
            const SizedBox(height: S.x3),
            Text(_error!, style: F.cap.copyWith(color: C.recRed)),
          ],
        ],
      ),
    );
  }

  List<Widget> _capture(BuildContext c, P p) => [
        SizedBox(
          height: S.x16 + S.x8,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < _photos.length; i++) ...[
                ClipRRect(
                  borderRadius: R.rLg,
                  child: Stack(children: [
                    Image.memory(_photos[i],
                        width: S.x16 + S.x8,
                        height: S.x16 + S.x8,
                        fit: BoxFit.cover),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Pressable(
                        onTap: () => setState(() => _photos.removeAt(i)),
                        semanticLabel: 'Remove photo',
                        child: SizedBox(
                          width: S.tap,
                          height: S.tap,
                          child: Icon(LucideIcons.x, size: I.md, color: C.white),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: S.x2),
              ],
              if (_photos.length < kFoodAiMaxPhotos) ...[
                _AddTile(LucideIcons.camera, 'Camera',
                    () => _add(ImageSource.camera)),
                const SizedBox(width: S.x2),
                _AddTile(LucideIcons.image, 'Gallery',
                    () => _add(ImageSource.gallery)),
              ],
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        OsTextField(
          controller: _note,
          label: _photos.isEmpty ? 'What did you eat?' : 'Anything to add? (optional)',
          hint: _photos.isEmpty
              ? 'e.g. two eggs on toast and a flat white'
              : 'e.g. half the rice, no sauce',
        ),
        const SizedBox(height: S.x4),
        ListenableBuilder(
          listenable: _note,
          builder: (_, _) => BigButton(
            _busy ? 'Reading…' : 'Estimate',
            icon: LucideIcons.sparkles,
            onTap: _busy || (_photos.isEmpty && _note.text.trim().isEmpty)
                ? null
                : _analyze,
          ),
        ),
      ];

  List<Widget> _review(BuildContext c, P p, List<FoodGuess> items) {
    double sum(double? Function(FoodGuess) f) =>
        items.fold<double>(0, (a, g) => a + (f(g) ?? 0));
    final unknownKcal = items.any((g) => g.kcal == null);
    return [
      RangeSegments(
        const ['Breakfast', 'Lunch', 'Dinner', 'Snack'],
        kMeals.indexOf(_meal),
        (i) => setState(() => _meal = kMeals[i]),
      ),
      const SizedBox(height: S.x3),
      for (var i = 0; i < items.length; i++) ...[
        _GuessCard(
          g: items[i],
          onGrams: (v) => setState(() => items[i] = items[i].at(v)),
          onName: (n) => items[i] = items[i].named(n),
          onRemove: () => setState(() => items.removeAt(i)),
        ),
        const SizedBox(height: S.x2),
      ],
      if (items.isNotEmpty) ...[
        const SizedBox(height: S.x2),
        Row(children: [
          Text('TOTAL', style: F.over.copyWith(color: p.ink3)),
          const Spacer(),
          Text(
            '${unknownKcal ? 'at least ' : ''}${sum((g) => g.kcal).round()} kcal · '
            '${sum((g) => g.proteinG).round()}P '
            '${sum((g) => g.carbsG).round()}C '
            '${sum((g) => g.fatG).round()}F',
            style: F.num(F.cap).copyWith(color: p.ink, fontWeight: FontWeight.w700),
          ),
        ]),
      ],
      const SizedBox(height: S.x4),
      BigButton(
        _busy
            ? 'Logging…'
            : items.length == 1
                ? 'Log it'
                : 'Log ${items.length} items',
        icon: LucideIcons.check,
        onTap: _busy || items.isEmpty ? null : _log,
      ),
      const SizedBox(height: S.x2),
      Center(
        child: TextAction('Start again', () => setState(() {
              _items = null;
              _error = null;
            })),
      ),
    ];
  }
}

class _AddTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AddTile(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: S.x16 + S.x8,
        decoration: BoxDecoration(color: p.card2, borderRadius: R.rLg),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: I.lg, color: p.ink),
          const SizedBox(height: S.x1),
          Text(label, style: F.cap.copyWith(color: p.ink2)),
        ]),
      ),
    );
  }
}

/// One proposed food: its name, its grams (stepped or typed), its numbers.
class _GuessCard extends StatefulWidget {
  final FoodGuess g;
  final ValueChanged<double> onGrams;
  final ValueChanged<String> onName;
  final VoidCallback onRemove;
  const _GuessCard({
    required this.g,
    required this.onGrams,
    required this.onName,
    required this.onRemove,
  });

  @override
  State<_GuessCard> createState() => _GuessCardState();
}

class _GuessCardState extends State<_GuessCard> {
  late final _name = TextEditingController(text: widget.g.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _n(double? v) => v == null ? '--' : '${v.round()}';

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final g = widget.g;
    final step = g.grams >= 100 ? 10.0 : 5.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(S.x3, S.x2, S.x1, S.x3),
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rLg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: AppField(
              bare: true,
              semanticLabel: 'Food name',
              controller: _name,
              onChanged: widget.onName,
              textStyle: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w700),
            ),
          ),
          Pressable(
            onTap: widget.onRemove,
            semanticLabel: 'Remove ${g.name}',
            child: SizedBox(
              width: S.tap,
              height: S.tap,
              child: Icon(LucideIcons.x, size: I.md, color: p.ink3),
            ),
          ),
        ]),
        Row(children: [
          Expanded(
            child: Text(
              '${_n(g.kcal)} kcal · ${_n(g.proteinG)}P ${_n(g.carbsG)}C ${_n(g.fatG)}F'
              '${g.portion.isEmpty ? '' : ' · ${g.portion}'}',
              style: F.num(F.cap).copyWith(color: p.ink2),
            ),
          ),
          _Step(LucideIcons.minus, 'Less',
              g.grams > step ? () => widget.onGrams(g.grams - step) : null),
          SizedBox(
            width: S.x16,
            child: Text('${g.grams.round()} g',
                textAlign: TextAlign.center,
                style: F.num(F.body)
                    .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
          ),
          _Step(LucideIcons.plus, 'More', () => widget.onGrams(g.grams + step)),
        ]),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _Step(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        width: S.tap,
        height: S.tap,
        child: Icon(icon,
            size: I.md, color: onTap == null ? p.ink3.withValues(alpha: .4) : p.ink),
      ),
    );
  }
}
