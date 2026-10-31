// A barcode Open Food Facts does not know, asked of USDA FoodData Central.
//
// FDC's Branded Foods set is the label data of hundreds of thousands of US
// packaged products, submitted by the manufacturers themselves, and it covers
// much of what OFF is missing. Same rules as off_lookup.dart: gated by the
// same consent ([offLookupAllowed]) — what leaves is the barcode and nothing
// else; user-initiated, one product per scan; a hit is cached in `food_def`
// by the caller; every value passes [gateNutrients] before it is offered, so a
// physically impossible figure arrives as an empty box, never as a number.
//
// ponytail: the public DEMO_KEY is rate-limited (about 30 requests an hour per
// address), which is plenty for a fallback a person triggers by scanning a
// packet. A rate-limited reply reads as unreachable. If that ever bites, ship a
// real api.data.gov key in the build config.
//
// FDC data is public domain (CC0); it is credited anyway ([kUsdaAttribution]).

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'off_lookup.dart';

const kUsdaAttribution =
    'Contains information from USDA FoodData Central (public domain).';

/// FDC's nutrient numbers → our field names. Branded values are per 100 g.
const _nutrients = <String, String>{
  '208': 'kcal',
  '203': 'protein',
  '205': 'carbs',
  '204': 'fat',
  '291': 'fibre',
  '269': 'sugar',
  '606': 'satFat',
  '307': 'sodiumMg',
};

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');

/// Pure: the product in an FDC search reply whose GTIN is [barcode], or null.
OffProduct? parseUsdaSearch(String barcode, Map<String, Object?> body) {
  final want = _digits(barcode);
  final foods = body['foods'];
  if (foods is! List || want.isEmpty) return null;
  for (final f in foods) {
    if (f is! Map || _digits('${f['gtinUpc'] ?? ''}') != want) continue;
    final label = '${f['description'] ?? ''}'.trim();
    if (label.isEmpty) continue;
    final raw = <String, double?>{};
    for (final n in (f['foodNutrients'] as List? ?? const [])) {
      if (n is! Map) continue;
      final key = _nutrients['${n['nutrientNumber'] ?? ''}'];
      final v = n['value'];
      if (key != null && v is num) raw[key] = v.toDouble();
    }
    final g = gateNutrients(raw);
    final unit = '${f['servingSizeUnit'] ?? ''}'.toLowerCase();
    final size = f['servingSize'];
    final servingG = size is num && (unit == 'g' || unit == 'grm') &&
            size > 0 &&
            size <= 2000
        ? size.toDouble()
        : null;
    String brand = '${f['brandName'] ?? f['brandOwner'] ?? ''}'.trim();
    if (brand.isNotEmpty) {
      brand = brand
          .split(' ')
          .map((w) => w.isEmpty
              ? w
              : w[0].toUpperCase() + w.substring(1).toLowerCase())
          .join(' ');
    }
    return OffProduct(
      barcode: barcode,
      label: label[0].toUpperCase() + label.substring(1).toLowerCase(),
      brand: brand,
      servingG: servingG,
      servingLabel: '${f['householdServingFullText'] ?? ''}'.trim(),
      kcal: g['kcal'],
      proteinG: g['protein'],
      carbsG: g['carbs'],
      fatG: g['fat'],
      fibreG: g['fibre'],
      sugarG: g['sugar'],
      satFatG: g['satFat'],
      sodiumMg: g['sodiumMg'],
    );
  }
  return null;
}

Future<OffResult> fetchUsdaProduct(String barcode, {http.Client? client}) async {
  if (!offLookupAllowed) return const OffResult(OffOutcome.refused);
  final code = _digits(barcode);
  if (code.isEmpty || code.length > 20) {
    return const OffResult(OffOutcome.notFound);
  }
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final res = await c.get(Uri.https('api.nal.usda.gov', '/fdc/v1/foods/search', {
      'query': code,
      'dataType': 'Branded',
      'pageSize': '10',
      'api_key': 'DEMO_KEY',
    })).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return const OffResult(OffOutcome.unreachable);
    final body = jsonDecode(res.body);
    if (body is! Map<String, Object?>) {
      return const OffResult(OffOutcome.unreachable);
    }
    final p = parseUsdaSearch(barcode, body);
    return p == null
        ? const OffResult(OffOutcome.notFound)
        : OffResult(OffOutcome.ok, p);
  } catch (_) {
    return const OffResult(OffOutcome.unreachable);
  } finally {
    if (owned) c.close();
  }
}

/// Open Food Facts first; FoodData Central when OFF has no such product. A
/// product OFF itself flags as wrong is not looked for elsewhere: the flag is
/// an answer. [usda] says which database answered.
Future<({OffResult result, bool usda})> lookupBarcode(String barcode,
    {http.Client? client}) async {
  final off = await fetchOffProduct(barcode, client: client);
  if (off.outcome != OffOutcome.notFound) return (result: off, usda: false);
  final fdc = await fetchUsdaProduct(barcode, client: client);
  return fdc.outcome == OffOutcome.ok
      ? (result: fdc, usda: true)
      : (result: off, usda: false);
}
