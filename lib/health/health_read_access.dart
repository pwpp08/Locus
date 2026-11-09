// Asking for READ access, and reading, without one refused type sinking the rest.
//
// Health Connect lets someone allow some kinds and not others, and after two
// refusals it stops showing the dialog and reports "nothing granted" even when
// earlier grants still stand. `hasPermissions` is all-or-nothing and
// `requestAuthorization` reflects only that last dialog, so taking either at
// its word told people with working access that they had none. The same trap
// on the read side: one refused type made a combined read throw, and the
// importers then reported an empty store.

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// True when at least one of [types] may be read after asking.
Future<bool> requestAnyHealthRead(
  Health health,
  List<HealthDataType> types,
) async {
  try {
    await health.configure();
    final perms = [for (final _ in types) HealthDataAccess.READ];
    if (await health.hasPermissions(types, permissions: perms) == true) {
      return true;
    }
    if (await health.requestAuthorization(types, permissions: perms)) {
      return true;
    }
    for (final t in types) {
      final ok = await health.hasPermissions(
        [t],
        permissions: const [HealthDataAccess.READ],
      );
      if (ok == true) return true;
    }
    return false;
  } catch (e) {
    debugPrint('[health] permission: $e');
    return false;
  }
}

/// [types] read one at a time; a type that is refused contributes nothing.
Future<List<HealthDataPoint>> readEachHealthType(
  Health health, {
  required List<HealthDataType> types,
  required DateTime start,
  required DateTime end,
}) async {
  final out = <HealthDataPoint>[];
  for (final t in types) {
    try {
      out.addAll(
        await health.getHealthDataFromTypes(
          types: [t],
          startTime: start,
          endTime: end,
        ),
      );
    } catch (e) {
      debugPrint('[health] read $t: $e');
    }
  }
  return out;
}
