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
}
