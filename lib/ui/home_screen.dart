import 'package:flutter/material.dart';

import '../app/game_controller.dart';
import 'game_screen.dart';
import 'upgrades_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final GameController controller;

  void _push(BuildContext context, Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final p = controller.progress;
        return Scaffold(
          backgroundColor: const Color(0xFF070B1A),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Text('${p.crystals} ◆',
                        style: const TextStyle(
                            fontSize: 20, color: Color(0xFF4DD0E1))),
                  ),
                  const Spacer(),
                  const Icon(Icons.rocket_launch,
                      size: 96, color: Color(0xFFE3F2FD)),
                  const SizedBox(height: 16),
                  const Text('PROBE DASH',
                      style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4)),
                  const SizedBox(height: 8),
                  Text('Best: ${p.bestDistance} m',
                      style: const TextStyle(
                          fontSize: 18, color: Color(0xFFFFD54F))),
                  const Spacer(),
                  FilledButton(
                    onPressed: () =>
                        _push(context, GameScreen(controller: controller)),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(240, 64)),
                    child: const Text('PLAY', style: TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _push(context, UpgradesScreen(controller: controller)),
                    icon: const Icon(Icons.upgrade),
                    label: const Text('Upgrades'),
                  ),
                  const Spacer(),
                  const Text('Prototype · test ads only',
                      style: TextStyle(color: Colors.white38)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
