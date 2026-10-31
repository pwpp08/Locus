// food_ai.dart — photos of a meal, or a sentence about it, into a list of
// foods with portions and nutrition, through the user's own AI key (the same
// provider and endpoint the Coach uses: CoachEngine.chatOnce).
//
// The model PROPOSES; nothing is written from here. The review sheet shows
// every item, its grams and its numbers, and only what the person confirms is
// logged — as a confirmed entry, which is the rule a photo estimate already
// lives under in nutrition_store.dart ([FoodEntry.sanitised]).
//
// Nothing is trusted on arrival. Every item's numbers go through the same
// physical gates a barcode's do ([gateNutrients], per 100 g): an impossible
// value comes back ABSENT and its box stays empty. A value the model says it
// cannot estimate is null, never a zero.

import 'dart:convert';
import 'dart:typed_data';

import '../coach/coach_config.dart';
import '../coach/coach_engine.dart';
import '../data/off_lookup.dart' show gateNutrients;

/// One food the model saw, at the portion it saw. Every figure is for
/// [grams] of it, and null where it is not known.
class FoodGuess {
  const FoodGuess({
    required this.name,
    required this.grams,
    this.portion = '',
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fibreG,
    this.sugarG,
    this.satFatG,
    this.sodiumMg,
  });

  final String name;
  final double grams;

  /// How the portion reads to a person ("1 bowl", "2 slices"). Shown only.
  final String portion;
  final double? kcal, proteinG, carbsG, fatG, fibreG, sugarG, satFatG, sodiumMg;

  /// The same food at [g] grams: every figure scaled by the same ratio.
  FoodGuess at(double g) {
    final k = grams <= 0 ? 0.0 : g / grams;
    double? s(double? v) => v == null ? null : v * k;
    return FoodGuess(
      name: name,
      grams: g,
      portion: g == grams ? portion : '',
      kcal: s(kcal),
      proteinG: s(proteinG),
      carbsG: s(carbsG),
      fatG: s(fatG),
      fibreG: s(fibreG),
      sugarG: s(sugarG),
      satFatG: s(satFatG),
      sodiumMg: s(sodiumMg),
    );
  }

  FoodGuess named(String n) => FoodGuess(
        name: n,
        grams: grams,
        portion: portion,
        kcal: kcal,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        fibreG: fibreG,
        sugarG: sugarG,
        satFatG: satFatG,
        sodiumMg: sodiumMg,
      );
}

const kFoodAiSystem = '''
You estimate the nutrition of food for a food log.
You get photos of a meal and/or a short description. Identify each separate food or drink, estimate the portion actually shown or described, and estimate its nutrition for that portion.
If a photo shows a nutrition label, read the label's values instead of estimating, and use the stated serving unless told otherwise.
Reply with ONLY a JSON object, no prose, no code fences:
{"items":[{"name":"Grilled chicken breast","portion":"1 fillet","grams":150,"kcal":248,"protein_g":46,"carbs_g":0,"fat_g":5.4,"fibre_g":0,"sugar_g":0,"sat_fat_g":1.5,"sodium_mg":110}]}
Rules: grams is the edible weight of the portion. Every number is for that whole portion. Use null for any value you cannot estimate; never guess a zero. Names are short and in English. If there is no food at all, reply {"items":[]}.
''';

/// Lenient parse of the model's reply (fences or prose around the object are
/// tolerated). Items without a name or a positive weight are dropped; every
/// figure is gated per 100 g, so an impossible one arrives as null.
List<FoodGuess> parseFoodAi(String raw) {
  var text = raw.trim();
  dynamic j;
  try {
    j = jsonDecode(text);
  } catch (_) {
    final s = text.indexOf('{'), e = text.lastIndexOf('}');
    if (s >= 0 && e > s) {
      try {
        j = jsonDecode(text.substring(s, e + 1));
      } catch (_) {}
    }
  }
  final items = j is Map ? j['items'] : null;
  if (items is! List) return const [];
  double? n(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
  final out = <FoodGuess>[];
  for (final it in items) {
    if (it is! Map) continue;
    final name = '${it['name'] ?? ''}'.trim();
    final grams = n(it['grams']);
    if (name.isEmpty || grams == null || grams <= 0 || grams > 5000) continue;
    // Per 100 g through the barcode gates, then back to the portion.
    final per = 100 / grams;
    double? p(String k) {
      final v = n(it[k]);
      return v == null ? null : v * per;
    }

    final g = gateNutrients({
      'kcal': p('kcal'),
      'protein': p('protein_g'),
      'carbs': p('carbs_g'),
      'fat': p('fat_g'),
      'fibre': p('fibre_g'),
      'sugar': p('sugar_g'),
      'satFat': p('sat_fat_g'),
      'sodiumMg': p('sodium_mg'),
    });
    double? back(String k) => g[k] == null ? null : g[k]! / per;
    out.add(FoodGuess(
      name: name.length > 80 ? name.substring(0, 80) : name,
      grams: grams,
      portion: '${it['portion'] ?? ''}'.trim(),
      kcal: back('kcal'),
      proteinG: back('protein'),
      carbsG: back('carbs'),
      fatG: back('fat'),
      fibreG: back('fibre'),
      sugarG: back('sugar'),
      satFatG: back('satFat'),
      sodiumMg: back('sodiumMg'),
    ));
  }
  return out;
}

/// The user turn: the description and the photos (JPEG bytes), in the content
/// shape [api] reads.
List<Map<String, dynamic>> foodAiContent(
  CoachApi api, {
  required String text,
  List<Uint8List> photos = const [],
}) {
  final prompt = text.trim().isEmpty
      ? 'Log what is in ${photos.length == 1 ? 'this photo' : 'these photos'}.'
      : text.trim();
  final responses = api == CoachApi.responses;
  return [
    {'type': responses ? 'input_text' : 'text', 'text': prompt},
    for (final ph in photos)
      responses
          ? {
              'type': 'input_image',
              'image_url': 'data:image/jpeg;base64,${base64Encode(ph)}',
            }
          : {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(ph)}'},
            },
  ];
}

/// Ask the model. Throws [CoachException] on a provider error; an empty list
/// means it found nothing it could call food.
Future<List<FoodGuess>> analyzeFood({
  required CoachConfig config,
  String text = '',
  List<Uint8List> photos = const [],
}) async {
  final raw = await CoachEngine.chatOnce(
    config: config,
    temperature: 0.2,
    messages: [
      {'role': 'system', 'content': kFoodAiSystem},
      {
        'role': 'user',
        'content': photos.isEmpty
            ? text
            : foodAiContent(config.api, text: text, photos: photos),
      },
    ],
  );
  return parseFoodAi(raw);
}
