import 'package:flutter/material.dart';

import '../app/game_controller.dart';
import '../logic/upgrades.dart';

/// Spend crystals on the four upgrades (spec US-3).
class UpgradesScreen extends StatelessWidget {
  const UpgradesScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final p = controller.progress;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Upgrades'),
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text('${p.crystals} ◆',
                      style: const TextStyle(
                          fontSize: 18, color: Color(0xFF4DD0E1))),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final u in Upgrades.all)
                _UpgradeTile(
                  info: u,
                  level: p.level(u.type),
                  crystals: p.crystals,
                  onBuy: () => controller.buyUpgrade(u.type),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _UpgradeTile extends StatelessWidget {
  const _UpgradeTile({
    required this.info,
    required this.level,
    required this.crystals,
    required this.onBuy,
  });

  final UpgradeInfo info;
  final int level;
  final int crystals;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final cost = Upgrades.nextCost(info.type, level);
    final affordable = cost != null && crystals >= cost;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${info.name}  Lv $level/${Upgrades.maxLevel}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(info.description,
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: level / Upgrades.maxLevel),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (cost == null)
            const Text('MAX', style: TextStyle(fontWeight: FontWeight.bold))
          else
            FilledButton(
              onPressed: affordable ? onBuy : null,
              child: Text(affordable
                  ? '$cost ◆'
                  : 'Need ${cost - crystals} ◆'), // US-3: show what's missing
            ),
        ]),
      ),
    );
  }
}
