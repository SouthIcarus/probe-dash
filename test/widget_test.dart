import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/app/game_controller.dart';
import 'package:probe_dash/config/env.dart';
import 'package:probe_dash/logic/progress.dart';
import 'package:probe_dash/logic/upgrades.dart';
import 'package:probe_dash/main.dart';
import 'package:probe_dash/services/ad_service.dart';
import 'package:probe_dash/services/save_store.dart';
import 'package:probe_dash/ui/home_screen.dart';
import 'package:probe_dash/ui/upgrades_screen.dart';

GameController controller(Directory dir, {int crystals = 0, int best = 0}) =>
    GameController(
      progress: Progress(crystals: crystals, bestDistance: best),
      store: SaveStore(dir),
      ads: AdService(enabled: false),
    );

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('probe_dash_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('home shows best distance, crystals, and play', (tester) async {
    await tester.pumpWidget(
      ProbeDashApp(controller: controller(dir, crystals: 42, best: 777)),
    );
    expect(find.text('PROBE DASH'), findsOneWidget);
    expect(find.text('Best: 777 m'), findsOneWidget);
    expect(find.text('42 ◆'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
  });

  testWidgets('home shows the dev build label with no defines (UI-2)', (
    tester,
  ) async {
    await tester.pumpWidget(ProbeDashApp(controller: controller(dir)));
    // `flutter test` may pass the pubspec version as FLUTTER_BUILD_NAME, so
    // match the prefix and check the build label key.
    final label = tester.widget<Text>(find.byKey(const Key('build-label')));
    expect(label.data, startsWith('DEV · test ads'));
  });

  testWidgets('home build label follows the flavor (UI-2)', (tester) async {
    Future<void> pumpWith(EnvConfig config) => tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: HomeScreen(controller: controller(dir), config: config),
      ),
    );

    await pumpWith(
      const EnvConfig(
        flavorName: 'beta',
        buildLabel: 'BETA',
        buildName: '0.2.0',
        buildNumber: '18',
      ),
    );
    expect(find.text('BETA 0.2.0 (18)'), findsOneWidget);

    await pumpWith(
      const EnvConfig(
        flavorName: 'dev',
        buildLabel: 'DEV',
        buildName: '0.1.0',
        buildNumber: '7',
      ),
    );
    expect(find.text('DEV · test ads · 0.1.0 (7)'), findsOneWidget);

    await pumpWith(
      const EnvConfig(
        flavorName: 'prod',
        buildName: '1.0.0',
        buildNumber: '30',
      ),
    );
    expect(find.byKey(const Key('build-label')), findsNothing);
    expect(find.text('PLAY'), findsOneWidget);
  });

  testWidgets('upgrades: buy when affordable, show shortfall when not', (
    tester,
  ) async {
    final c = controller(dir, crystals: 120);
    await tester.pumpWidget(MaterialApp(home: UpgradesScreen(controller: c)));

    // Crystal Value costs 100: affordable.
    await tester.runAsync(() async {
      await tester.tap(find.text('100 ◆'));
      await tester.pump();
      await c.store.save(c.progress); // queued after the tap's save
    });
    await tester.pump();
    expect(c.progress.level(UpgradeType.crystalValue), 1);
    expect(c.progress.crystals, 20);
    expect(File('${dir.path}/save.json').existsSync(), isTrue);

    // Shield costs 250: shows how many crystals are missing.
    expect(find.text('Need 230 ◆'), findsOneWidget);
  });
}
