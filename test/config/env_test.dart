import 'package:flutter_test/flutter_test.dart';
import 'package:probe_dash/config/env.dart';

// A well-formed, NON-test ad unit ID. Built at runtime so that no real-looking
// ID is ever written in a committed file (the repo guard,
// .github/scripts/check_ad_ids.py, would rightly fail on one).
final String fakeRealRewarded = 'ca-app-pub-${'1' * 16}/${'2' * 10}';
final String fakeRealInterstitial = 'ca-app-pub-${'1' * 16}/${'3' * 10}';

EnvConfig cfg({
  String flavor = 'prod',
  String appFlavor = 'prod',
  String adsMode = 'real',
  String rewarded = '',
  String interstitial = '',
  String analytics = 'off',
  String buildLabel = '',
  String debugMenu = 'false',
  String buildName = '',
  String buildNumber = '',
}) => EnvConfig(
  flavorName: flavor,
  appFlavor: appFlavor,
  adsMode: adsMode,
  rewardedId: rewarded.isEmpty ? fakeRealRewarded : rewarded,
  interstitialId: interstitial.isEmpty ? fakeRealInterstitial : interstitial,
  analytics: analytics,
  buildLabel: buildLabel,
  debugMenu: debugMenu,
  buildName: buildName,
  buildNumber: buildNumber,
);

void main() {
  group('defaults with no defines (flutter test, local runs)', () {
    const e = EnvConfig.fromEnvironment();

    test('flavor is dev and the build is not prod', () {
      expect(e.flavor, Flavor.dev);
      expect(e.isProd, isFalse);
    });

    test('ad units are the Google test units', () {
      expect(e.adUnitIds(ios: false), androidTestAdUnits);
      expect(e.adUnitIds(ios: true), iosTestAdUnits);
      expect(e.rewardedId, androidTestAdUnits.rewarded);
      expect(e.interstitialId, androidTestAdUnits.interstitial);
    });

    test('analytics and the debug menu are off', () {
      expect(e.analyticsEnabled, isFalse);
      expect(e.debugMenuEnabled, isFalse);
    });

    test('the global env is the same', () {
      expect(env.adUnitIds(ios: false), androidTestAdUnits);
      expect(env.analyticsEnabled, isFalse);
    });
  });

  group('test units are Google sample units', () {
    test('all four are well-formed test IDs', () {
      for (final id in [
        androidTestAdUnits.rewarded,
        androidTestAdUnits.interstitial,
        iosTestAdUnits.rewarded,
        iosTestAdUnits.interstitial,
      ]) {
        expect(isWellFormedAdUnitId(id), isTrue, reason: id);
        expect(isTestAdUnitId(id), isTrue, reason: id);
      }
    });

    test('the fake real IDs are well-formed but not test IDs', () {
      expect(isWellFormedAdUnitId(fakeRealRewarded), isTrue);
      expect(isTestAdUnitId(fakeRealRewarded), isFalse);
    });

    test('malformed IDs are rejected', () {
      for (final id in [
        '',
        'ca-app-pub-123/456',
        'ca-app-pub-$testAdPublisher~3347511713', // an app ID, not a unit
        ' ca-app-pub-$testAdPublisher/5224354917',
        'ca-app-pub-$testAdPublisher/5224354917 ',
        'xx-app-pub-${'1' * 16}/${'2' * 10}',
      ]) {
        expect(isWellFormedAdUnitId(id), isFalse, reason: id);
      }
    });
  });

  group('parseFlavor', () {
    test('exact names map to their flavor', () {
      expect(parseFlavor('dev'), Flavor.dev);
      expect(parseFlavor('beta'), Flavor.beta);
      expect(parseFlavor('prod'), Flavor.prod);
    });

    test('anything else is dev (the safe choice)', () {
      for (final raw in ['', 'PROD', 'Prod', 'production', ' prod', 'x']) {
        expect(parseFlavor(raw), Flavor.dev, reason: raw);
      }
    });
  });

  group('AD-3 / ENV-3 runtime fallback', () {
    test('a prod build in real mode on Android uses the real IDs', () {
      final ids = cfg().adUnitIds(ios: false);
      expect(ids.rewarded, fakeRealRewarded);
      expect(ids.interstitial, fakeRealInterstitial);
    });

    test('dev and beta never get a real ID, whatever else is set', () {
      for (final flavor in ['dev', 'beta', '', 'PROD', 'x']) {
        for (final appFlavor in ['', 'dev', 'beta', 'prod']) {
          for (final mode in ['test', 'real', '']) {
            for (final ios in [false, true]) {
              final ids = cfg(
                flavor: flavor,
                appFlavor: appFlavor,
                adsMode: mode,
              ).adUnitIds(ios: ios);
              final why =
                  'FLAVOR=$flavor app=$appFlavor ADS_MODE=$mode ios=$ios';
              expect(isTestAdUnitId(ids.rewarded), isTrue, reason: why);
              expect(isTestAdUnitId(ids.interstitial), isTrue, reason: why);
            }
          }
        }
      }
    });

    test('prod config inside a dev or beta Gradle flavor gets test IDs', () {
      for (final appFlavor in ['', 'dev', 'beta']) {
        final ids = cfg(appFlavor: appFlavor).adUnitIds(ios: false);
        expect(ids, androidTestAdUnits, reason: appFlavor);
      }
    });

    test('prod in test mode gets test IDs', () {
      expect(cfg(adsMode: 'test').adUnitIds(ios: false), androidTestAdUnits);
    });

    test('prod on iOS gets the iOS test IDs (no iOS release exists)', () {
      expect(cfg().adUnitIds(ios: true), iosTestAdUnits);
    });

    test('malformed or missing real IDs fall back to test IDs one by one', () {
      final ids = cfg(rewarded: 'not-an-id').adUnitIds(ios: false);
      expect(ids.rewarded, androidTestAdUnits.rewarded);
      expect(ids.interstitial, fakeRealInterstitial);

      const empty = EnvConfig(
        flavorName: 'prod',
        appFlavor: 'prod',
        adsMode: 'real',
      );
      expect(empty.adUnitIds(ios: false), androidTestAdUnits);
    });
  });

  group('analytics (AN-6) and debug menu (ENV-9)', () {
    test(
      'analytics is on only in matching beta/prod builds with ANALYTICS=on',
      () {
        expect(
          cfg(
            flavor: 'beta',
            appFlavor: 'beta',
            analytics: 'on',
          ).analyticsEnabled,
          isTrue,
        );
        expect(cfg(analytics: 'on').analyticsEnabled, isTrue);
        expect(
          cfg(
            flavor: 'dev',
            appFlavor: 'dev',
            analytics: 'on',
          ).analyticsEnabled,
          isFalse,
        );
        expect(
          cfg(
            flavor: 'beta',
            appFlavor: 'dev',
            analytics: 'on',
          ).analyticsEnabled,
          isFalse,
        );
        expect(
          cfg(flavor: 'beta', appFlavor: '', analytics: 'on').analyticsEnabled,
          isFalse,
        );
        expect(cfg(analytics: 'off').analyticsEnabled, isFalse);
      },
    );

    test('the debug menu is dev only', () {
      expect(cfg(flavor: 'dev', debugMenu: 'true').debugMenuEnabled, isTrue);
      expect(cfg(flavor: 'beta', debugMenu: 'true').debugMenuEnabled, isFalse);
      expect(cfg(flavor: 'prod', debugMenu: 'true').debugMenuEnabled, isFalse);
      expect(cfg(flavor: 'dev', debugMenu: 'false').debugMenuEnabled, isFalse);
    });
  });

  group('Home build label (UI-2, spec v3)', () {
    test('dev: "DEV · test ads" plus the version', () {
      expect(
        cfg(
          flavor: 'dev',
          buildLabel: 'DEV',
          buildName: '0.1.0',
          buildNumber: '42',
        ).homeBuildLabel,
        'DEV · test ads · 0.1.0 (42)',
      );
      expect(
        cfg(flavor: 'dev', buildLabel: 'DEV').homeBuildLabel,
        'DEV · test ads',
      );
    });

    test('beta: "BETA X.Y.Z (N)"', () {
      expect(
        cfg(
          flavor: 'beta',
          buildLabel: 'BETA',
          buildName: '0.2.0',
          buildNumber: '18',
        ).homeBuildLabel,
        'BETA 0.2.0 (18)',
      );
    });

    test('prod: no label', () {
      expect(
        cfg(
          buildLabel: 'X',
          buildName: '1.0.0',
          buildNumber: '30',
        ).homeBuildLabel,
        isNull,
      );
    });

    test('defaults show the dev label', () {
      expect(const EnvConfig().homeBuildLabel, 'DEV · test ads');
    });
  });
}
