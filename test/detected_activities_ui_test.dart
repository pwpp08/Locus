import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/compute/manual_session.dart';
import 'package:openstrap_edge/models/activity_suggestion.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/screens/detected_activities.dart';
import 'package:openstrap_edge/ui2/screens/home/home_my_day.dart';
import 'package:openstrap_edge/ui2/screens/window_editor.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';

ActivitySuggestion proposal(
  String id,
  ActivityKind kind, {
  int revision = 0,
  int shift = 0,
}) => ActivitySuggestion(
  id: id,
  kind: kind,
  startTs: 1787157000 + shift,
  endTs: 1787158800 + shift,
  revision: revision,
  details: const {'sport': 'unrecognized'},
);

class _Repo extends LocalRepository {
  List<ActivitySuggestion> items = [
    proposal('nap', ActivityKind.nap),
    proposal('workout', ActivityKind.workout),
  ];
  bool fail = false;
  String? savedType;
  @override
  Future<List<ActivitySuggestion>> pendingActivities() async {
    if (fail) throw StateError('offline database');
    return items.toList();
  }

  @override
  Future<int> pendingActivityCount() async {
    if (fail) throw StateError('offline database');
    return items.length;
  }

  @override
  Future<List<Map<String, dynamic>>> getSessions({
    int? from,
    int? to,
    bool includeDetected = true,
  }) async => [
    {'type': 'Running', 'start_ts': 1787000000, 'end_ts': 1787003600},
  ];

  @override
  Future<List<SessionSpan>> savedSessionSpans() async => [];
  @override
  Future<void> discardActivity(ActivitySuggestion s) async {
    items.removeWhere((i) => i.id == s.id);
  }

  @override
  Future<void> confirmActivity(
    ActivitySuggestion s, {
    int? startTs,
    int? endTs,
    String? workoutType,
  }) async {
    if (items.singleWhere((i) => i.id == s.id).revision != s.revision) {
      throw const ActivityReviewException(
        'The proposal changed. Review the new times.',
      );
    }
    savedType = workoutType;
    items.removeWhere((i) => i.id == s.id);
  }
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'notify_auto_detect': false}),
  );
  Future<_Repo> pump(WidgetTester t, {bool fail = false, Widget? home}) async {
    t.view.physicalSize = const Size(1170, 6000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final repo = _Repo()..fail = fail;
    app.repo = repo;
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<ThemeController>(
            create: (_) =>
                ThemeController.seed(AppThemeChoice.light, Brightness.light),
          ),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: home ?? const DetectedActivitiesScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
    return repo;
  }

  testWidgets('load failure offers retry and does not claim an empty list', (
    t,
  ) async {
    final repo = await pump(t, fail: true);
    expect(find.text('Could not load activities. Try again.'), findsOneWidget);
    expect(find.text('Nothing to review'), findsNothing);
    repo.fail = false;
    await t.tap(find.text('TRY AGAIN'));
    await t.pumpAndSettle();
    expect(find.text('POSSIBLE NAP'), findsOneWidget);
  });

  testWidgets('the review lists naps only: a workout waits in My Day', (
    t,
  ) async {
    await pump(t);
    expect(find.text('POSSIBLE NAP'), findsOneWidget);
    expect(find.text('POSSIBLE WORKOUT'), findsNothing);
  });

  testWidgets('confirming a nap leaves the workout pending', (t) async {
    final repo = await pump(t);
    await t.tap(find.text('CONFIRM').first);
    await t.pumpAndSettle();
    expect(repo.items.single.id, 'workout');
    expect(find.text('Nothing to review'), findsOneWidget);
  });

  testWidgets('cancelling a nap edit leaves it pending', (t) async {
    final repo = await pump(t);
    await t.tap(find.text('EDIT').first);
    await t.pumpAndSettle();
    expect(find.text('SAVE AND CONFIRM'), findsOneWidget);
    Navigator.of(t.element(find.byType(WindowEditor))).pop();
    await t.pumpAndSettle();
    expect(repo.items, hasLength(2));
  });

  testWidgets('home card stays up when the count fails to load', (t) async {
    await pump(t, fail: true, home: const Scaffold(body: DetectedActivitiesCard()));
    expect(find.text('Detected activities'), findsOneWidget);
    expect(find.text('Could not load activities. Try again.'), findsOneWidget);
  });

  group('a detected workout', () {
    testWidgets('shows in My Day as ACTIVITY, without a made-up strain', (
      t,
    ) async {
      ActivitySuggestion? tapped;
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: HomeMyDay(
            day: '2026-08-19',
            night: const {},
            sessions: const [],
            detected: [proposal('workout', ActivityKind.workout)],
            onDetected: (s) => tapped = s,
            onExpand: () {},
            onSleep: () {},
            onSession: (_) {},
            onAdd: () {},
          ),
        ),
      ));
      expect(find.text('ACTIVITY'), findsOneWidget);
      // Thirty minutes: its length, the only figure known before it is named.
      expect(find.text('0:30'), findsOneWidget);
      await t.tap(find.text('ACTIVITY'));
      expect(tapped?.id, 'workout');
    });

    testWidgets('asks what it was, offers the last one, and saves the answer', (
      t,
    ) async {
      final repo = await pump(t, home: const IdentifyActivityScreen());
      expect(find.text('SELECT YOUR ACTIVITY'), findsOneWidget);
      expect(find.text('MOST RECENT'), findsOneWidget);
      expect(find.text('ALL A-Z'), findsOneWidget);
      await t.tap(find.text('RUNNING').first);
      await t.pumpAndSettle();
      expect(repo.savedType, 'running');
      expect(repo.items.single.id, 'nap');
    });

    testWidgets('a window that moved is saved at its latest revision', (
      t,
    ) async {
      final repo = await pump(t, home: const IdentifyActivityScreen());
      repo.items[1] = proposal(
        'workout',
        ActivityKind.workout,
        revision: 1,
        shift: 600,
      );
      await t.tap(find.text('RUNNING').first);
      await t.pumpAndSettle();
      expect(repo.savedType, 'running');
    });

    testWidgets('can be thrown away from the same question', (t) async {
      final repo = await pump(t, home: const IdentifyActivityScreen());
      await t.tap(find.byIcon(LucideIcons.trash2));
      await t.pumpAndSettle();
      expect(repo.items.single.id, 'nap');
      expect(repo.savedType, isNull);
    });

  });
}
