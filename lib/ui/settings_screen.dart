import 'package:flutter/material.dart';

import '../app/game_controller.dart';
import '../config/privacy_policy.dart';

/// Settings: vibration on/off (A-29, D4), privacy choices (SEC-5), the
/// privacy policy inside the app (LEG-1) and the licence page.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<bool> _privacyChoices;

  GameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _privacyChoices = controller.ads.privacyOptionsRequired();
  }

  Future<void> _openPrivacyChoices() async {
    await controller.ads.showPrivacyOptions();
    if (!mounted) return;
    // The requirement can change with the answer (SEC-5): read it again.
    setState(() {
      _privacyChoices = controller.ads.privacyOptionsRequired();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B1A),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF070B1A),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListView(
            children: [
              SwitchListTile(
                key: const Key('settings-haptics'),
                title: const Text('Vibration'),
                subtitle: const Text('Buzz on crashes, near misses and records'),
                value: controller.progress.hapticsOn,
                onChanged: controller.setHaptics,
              ),
              FutureBuilder<bool>(
                future: _privacyChoices,
                builder: (context, snap) => snap.data == true
                    ? ListTile(
                        key: const Key('settings-privacy-choices'),
                        leading: const Icon(Icons.tune),
                        title: const Text('Privacy choices'),
                        subtitle: const Text('Change your ad consent'),
                        onTap: _openPrivacyChoices,
                      )
                    : const SizedBox.shrink(),
              ),
              ListTile(
                key: const Key('settings-privacy-policy'),
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy policy'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PrivacyPolicyScreen(),
                  ),
                ),
              ),
              ListTile(
                key: const Key('settings-licences'),
                leading: const Icon(Icons.description_outlined),
                title: const Text('Licences'),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Probe Dash',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The privacy policy as text inside the app, so it can be read without a
/// browser and without leaving the game.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B1A),
      appBar: AppBar(
        title: const Text('Privacy policy'),
        backgroundColor: const Color(0xFF070B1A),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Probe Dash privacy policy',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Last updated: $privacyPolicyUpdated',
              style: TextStyle(color: Colors.white60),
            ),
            for (final (title, body) in privacyPolicySections) ...[
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(body, style: const TextStyle(height: 1.45)),
            ],
            const SizedBox(height: 20),
            const SelectableText(
              'Also online: $privacyPolicyUrl',
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
