import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/game_controller.dart';
import 'services/ad_service.dart';
import 'services/save_store.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final store = SaveStore();
  final controller = GameController(
    progress: await store.load(),
    store: store,
    ads: AdService(),
  );

  runApp(ProbeDashApp(controller: controller));

  // Consent form + ads load after the first frame, so the game opens fast.
  WidgetsBinding.instance
      .addPostFrameCallback((_) => controller.ads.init());
}

class ProbeDashApp extends StatelessWidget {
  const ProbeDashApp({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Probe Dash',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF1E88E5),
        useMaterial3: true,
      ),
      home: HomeScreen(controller: controller),
    );
  }
}
