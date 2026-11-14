import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_timer/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('starts with the default focus timer and supports pause/reset', (
    tester,
  ) async {
    await tester.pumpWidget(const FocusTimerApp());
    await tester.pumpAndSettle();

    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('0 sessions completed today'), findsOneWidget);

    await tester.tap(find.text('Short'));
    await tester.pumpAndSettle();
    expect(find.text('05:00'), findsOneWidget);

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Start'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('05:00'), findsOneWidget);
  });

  testWidgets('saves custom timer durations', (tester) async {
    await tester.pumpWidget(const FocusTimerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Timer settings'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '30');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('30:00'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('timer.durations'),
      '{"focus":30,"shortBreak":5,"longBreak":15}',
    );
  });

  testWidgets('catches up sessions completed while the app was suspended', (
    tester,
  ) async {
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues({
      'timer.mode': 'focus',
      'timer.running': true,
      'timer.deadline': now
          .subtract(const Duration(seconds: 25))
          .millisecondsSinceEpoch,
      'sessions.today': 0,
      'sessions.date': today,
      'sessions.history': '[]',
    });

    await tester.pumpWidget(const FocusTimerApp());
    await tester.pumpAndSettle();

    expect(find.text('Short break'), findsOneWidget);
    expect(find.text('1 session completed today'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('timer.running'), isTrue);
    final restoredDeadline = DateTime.fromMillisecondsSinceEpoch(
      preferences.getInt('timer.deadline')!,
    );
    expect(restoredDeadline.isAfter(DateTime.now()), isTrue);
    expect(
      restoredDeadline.isBefore(
        DateTime.now().add(const Duration(seconds: 285)),
      ),
      isTrue,
    );
    expect(
      preferences.getString('sessions.history'),
      contains('"mode":"focus"'),
    );
  });
}
