// Lowercase in a sentence: the signal name mid-caption.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/l10n/app_localizations.dart';
import 'package:openstrap_edge/ui2/screens/screens.dart';

void main() {

  test('english still lowercases it', () {
    final l = lookupAppLocalizations(const Locale('en'));
    expect(nounInSentence(l, 'Resting heart rate'), 'resting heart rate');
    expect(nounInSentence(null, 'Resting heart rate'), 'resting heart rate');
  });
}
