// COMMUNITY — teams and their boards, team chat, and Humans (the people you
// follow).
//
// Laid out after the reference flows "Joining a team" through "Editing rank
// display" (refs/community/sheet00-13.png) and the user's own Humans
// screenshots (refs/community/humans_*.jpg): layout and behaviour, never the
// other brand's name or art.
//
// Signed out it is an intro and one way in; the rest of the app works the same
// without it. One library in several part files, so the screens can share
// their private pieces without each becoming public vocabulary.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../community/community_service.dart';
import '../../community/leaderboard.dart';
import '../../data/day_label.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../../theme/theme_switcher.dart' show themedRoute;
import '../activity/catalogue.dart' show activityByName;
import '../profile/data_highlights.dart'
    show DataHighlightsScreen;
import '../profile/profile.dart' show SetRow, settingsGroup;
import '../screens/dial_parts.dart' show dialSeries;
import '../screens/home_screen.dart' show go, repoOf;
import '../ui2.dart';

part 'community_parts.dart';
part 'community_intro.dart';
part 'community_home.dart';
part 'team_join.dart';
part 'team_create.dart';
part 'team_screen.dart';
part 'team_board.dart';
part 'team_chat.dart';
part 'member_profile.dart';
part 'humans.dart';
