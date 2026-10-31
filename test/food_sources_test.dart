// The two new ways a food arrives: a barcode Open Food Facts did not know,
// found in USDA FoodData Central, and an AI estimate from a photo or a
// sentence. Both go through the same physical gates as a scanned label.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ai/food_ai.dart';
import 'package:openstrap_edge/data/usda_lookup.dart';

void main() {
  group('parseUsdaSearch', () {
    Map<String, Object?> reply(String gtin, {num kcal = 250}) => {
          'foods': [
            {
              'gtinUpc': gtin,
              'description': 'PEANUT BUTTER CUPS',
              'brandOwner': 'ACME FOODS',
              'servingSize': 42,
              'servingSizeUnit': 'g',
              'householdServingFullText': '2 cups',
              'foodNutrients': [
                {'nutrientNumber': '208', 'value': kcal},
                {'nutrientNumber': '203', 'value': 9.5},
                {'nutrientNumber': '307', 'value': 360},
              ],
            },
          ],
        };

    test('the product whose GTIN matches, leading zeros aside', () {
      final p = parseUsdaSearch('0034000002405', reply('34000002405'))!;
      expect(p.label, 'Peanut butter cups');
      expect(p.brand, 'Acme Foods');
      expect(p.servingG, 42);
      expect((p.kcal, p.proteinG, p.sodiumMg), (250, 9.5, 360));
      expect(p.carbsG, isNull, reason: 'not reported is not zero');
    });

    test('another product is not this one', () {
      expect(parseUsdaSearch('111', reply('222')), isNull);
    });

    test('an impossible figure arrives empty', () {
      expect(parseUsdaSearch('5', reply('5', kcal: 2500))!.kcal, isNull);
    });
  });

  group('parseFoodAi', () {
    test('items with their portions; fences and prose tolerated', () {
      final g = parseFoodAi('Sure!\n```json\n{"items":[{"name":"Rice",'
          '"portion":"1 bowl","grams":200,"kcal":260,"protein_g":5,'
          '"carbs_g":56,"fat_g":null}]}\n```');
      expect(g, hasLength(1));
      expect((g.single.name, g.single.grams, g.single.kcal), ('Rice', 200, 260));
      expect(g.single.fatG, isNull);
    });

    test('a portion can be rescaled', () {
      final g = parseFoodAi('{"items":[{"name":"Rice","grams":200,"kcal":260}]}')
          .single
          .at(100);
      expect((g.grams, g.kcal), (100, 130));
    });

    test('nameless, weightless and impossible items are dropped or emptied',
        () {
      final g = parseFoodAi('{"items":[{"name":"","grams":10},'
          '{"name":"Air","grams":0},'
          '{"name":"Oil","grams":10,"kcal":500}]}');
      expect(g.single.name, 'Oil');
      expect(g.single.kcal, isNull, reason: '5,000 kcal per 100 g is not food');
    });

    test('nothing parseable is nothing', () {
      expect(parseFoodAi('I cannot see any food.'), isEmpty);
    });
  });
}
