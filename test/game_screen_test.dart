import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/logic/run_session.dart';
import 'package:probe_dash/ui/game_screen.dart';

import 'support/fakes.dart';

void main() {
  Future<void> pumpGame(WidgetTester tester, c) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(controller: c)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  group('A-20 one run, one result', () {
    testWidgets('double tap on "No thanks" applies the run once',
        (tester) async {
      final c = makeController(ads: FakeAds(ready: true));
      await pumpGame(tester, c);
      gameOf(tester).session!.rawCrystals = 7;
      await crashNow(tester);
      expect(gameOf(tester).phase.value, RunPhase.crashed);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('CONTINUE?'), findsOneWidget);

      // Two taps inside one frame: both reach the button before it rebuilds.
      await tester.tap(find.text('No thanks'));
      await tester.tap(find.text('No thanks'));
      await tester.pump(const Duration(seconds: 1));

      expect(c.progress.runs, 1);
      expect(c.progress.crystals, 7);
      expect(find.text('PLAY AGAIN'), findsOneWidget);
    });

    testWidgets('countdown ending as the player taps applies the run once',
        (tester) async {
      final c = makeController(ads: FakeAds(ready: true));
      await pumpGame(tester, c);
      gameOf(tester).session!.rawCrystals = 3;
      await crashNow(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('CONTINUE?'), findsOneWidget);

      // Let the countdown reach its last second, then tap "No thanks" just
      // before it hits 0 and let it hit 0 too.
      await tester.pump(const Duration(milliseconds: 3900));
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.text('No thanks'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));

      expect(c.progress.runs, 1);
      expect(c.progress.crystals, 3);
    });
  });
}
