import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/config/privacy_policy.dart';
import 'package:probe_dash/game/haptics.dart';
import 'package:probe_dash/logic/progress.dart';
import 'package:probe_dash/ui/home_screen.dart';
import 'package:probe_dash/ui/settings_screen.dart';

import 'support/fakes.dart';

void main() {
  tearDown(() => Haptics.enabled = true);

  group('Settings', () {
    testWidgets('Home opens Settings', (tester) async {
      final c = makeController();
      await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await tester.tap(find.byKey(const Key('home-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Vibration'), findsOneWidget);
    });

    testWidgets('the vibration switch turns haptics off and saves it',
        (tester) async {
      final c = makeController();
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(controller: c)));
      expect(c.progress.hapticsOn, isTrue);

      await tester.tap(find.byKey(const Key('settings-haptics')));
      await tester.pump();
      expect(c.progress.hapticsOn, isFalse);
      expect(Haptics.enabled, isFalse);
      // The choice survives a restart: it is in the saved JSON.
      expect(Progress.fromJson(c.progress.toJson()).hapticsOn, isFalse);

      await tester.tap(find.byKey(const Key('settings-haptics')));
      await tester.pump();
      expect(Haptics.enabled, isTrue);
    });

    testWidgets('no "Privacy choices" where consent rules do not apply',
        (tester) async {
      final c = makeController();
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(controller: c)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-privacy-choices')), findsNothing);
    });

    testWidgets('SEC-5: "Privacy choices" opens Google\'s form when required',
        (tester) async {
      final ads = FakeAds()..privacyRequired = true;
      final c = makeController(ads: ads);
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(controller: c)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-privacy-choices')));
      await tester.pumpAndSettle();
      expect(ads.privacyOptionsShown, 1);
    });

    testWidgets('LEG-1: the privacy policy can be read inside the app',
        (tester) async {
      final c = makeController();
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(controller: c)));
      await tester.tap(find.byKey(const Key('settings-privacy-policy')));
      await tester.pumpAndSettle();
      expect(find.text('Probe Dash privacy policy'), findsOneWidget);
      expect(find.text('In short'), findsOneWidget);
      expect(find.textContaining('Google AdMob'), findsWidgets);
    });
  });

  group('Saved settings', () {
    test('old saves without settings keep vibration on', () {
      expect(Progress.fromJson({'crystals': 5}).hapticsOn, isTrue);
      expect(Progress.fromJson({'settings': 'junk'}).hapticsOn, isTrue);
      expect(
          Progress.fromJson({
            'settings': {'haptics': false}
          }).hapticsOn,
          isFalse);
    });
  });

  group('Privacy policy', () {
    test('the page published online says the same as the app (LEG-1)', () {
      String flat(String s) => s
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&gt;', '>')
          .replaceAll(RegExp(r'\s+'), ' ');
      final page = flat(File('docs/privacy.html').readAsStringSync());
      expect(page, contains('Last updated: $privacyPolicyUpdated'));
      for (final (title, body) in privacyPolicySections) {
        expect(page, contains(title), reason: title);
        expect(page, contains(flat(body)), reason: title);
      }
    });

    test('the policy names what version 1.0 really does', () {
      final all = privacyPolicySections.map((s) => s.$2).join(' ');
      expect(all, contains('advertising ID'));
      expect(all, contains('Privacy choices'));
      expect(all, contains('under 13'));
      expect(all, isNot(contains('Firebase'))); // no analytics in 1.0
      expect(privacyPolicyUrl, startsWith('https://'));
    });
  });
}
