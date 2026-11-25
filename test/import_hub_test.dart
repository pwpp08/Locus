// The "last imported" wording on the Import screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/profile/import_hub.dart';

void main() {
  final now = DateTime(2026, 11, 25, 12);
  test('how long ago, in the unit that fits', () {
    expect(importedAgo(now.subtract(const Duration(seconds: 20)), now), 'just now');
    expect(importedAgo(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
    expect(importedAgo(now.subtract(const Duration(hours: 3)), now), '3 h ago');
    expect(importedAgo(DateTime(2026, 11, 24, 8), now), 'yesterday');
    expect(importedAgo(DateTime(2026, 11, 12, 8), now), '12 Nov');
  });
}
