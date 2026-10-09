// Build environment config (spec v3 OPS-1, OPS-2, AD-3, AN-6, UI-2;
// release/environments.md §4). Pure Dart: no Flutter imports, so
// `flutter test` covers every rule here.
//
// Values come from `--dart-define-from-file=config/<flavor>.json` (and, for
// prod releases only, CI-injected `--dart-define-from-file` with the real
// ad unit IDs). With no defines at all (`flutter test`, a bare local run)
// every default is the safe one: flavor dev, Google test ads, no analytics.

/// The three build flavors (OPS-1).
enum Flavor { dev, beta, prod }

/// Google's public sample-ads publisher. IDs under it are test IDs: safe to
/// tap, never earn money (AD-3).
const String testAdPublisher = '3940256099942544';

/// Rewarded and interstitial ad unit IDs for one platform.
class AdUnitIds {
  const AdUnitIds({required this.rewarded, required this.interstitial});

  final String rewarded;
  final String interstitial;

  @override
  bool operator ==(Object other) =>
      other is AdUnitIds &&
      other.rewarded == rewarded &&
      other.interstitial == interstitial;

  @override
  int get hashCode => Object.hash(rewarded, interstitial);

  @override
  String toString() => 'AdUnitIds($rewarded, $interstitial)';
}

/// Google's documented Android test ad units.
const AdUnitIds androidTestAdUnits = AdUnitIds(
  rewarded: 'ca-app-pub-$testAdPublisher/5224354917',
  interstitial: 'ca-app-pub-$testAdPublisher/1033173712',
);

/// Google's documented iOS test ad units.
const AdUnitIds iosTestAdUnits = AdUnitIds(
  rewarded: 'ca-app-pub-$testAdPublisher/1712485313',
  interstitial: 'ca-app-pub-$testAdPublisher/4411468910',
);

final RegExp _adUnitIdPattern = RegExp(r'^ca-app-pub-(\d{16})/\d{10}$');

/// True if [id] is a well-formed AdMob ad unit ID
/// (`ca-app-pub-<16 digits>/<10 digits>`).
bool isWellFormedAdUnitId(String id) => _adUnitIdPattern.hasMatch(id);

/// True if [id] is an ad unit ID of Google's test publisher.
bool isTestAdUnitId(String id) =>
    _adUnitIdPattern.firstMatch(id)?.group(1) == testAdPublisher;

/// Parses a flavor name. Anything that is not exactly `beta` or `prod`
/// (empty, a typo, a different case) is [Flavor.dev], the safe choice.
Flavor parseFlavor(String raw) => switch (raw) {
  'prod' => Flavor.prod,
  'beta' => Flavor.beta,
  _ => Flavor.dev,
};

/// One build's environment, from compile-time defines.
class EnvConfig {
  const EnvConfig({
    this.flavorName = 'dev',
    this.appFlavor = '',
    this.adsMode = 'test',
    this.analytics = 'off',
    this.buildLabel = 'DEV',
    this.debugMenu = 'false',
    this.rewardedId = '',
    this.interstitialId = '',
    this.buildName = '',
    this.buildNumber = '',
  });

  /// Reads the compile-time defines of this build.
  const EnvConfig.fromEnvironment()
    : flavorName = const String.fromEnvironment('FLAVOR', defaultValue: 'dev'),
      // Set by `flutter build/run --flavor <name>` (Flutter's `appFlavor`).
      appFlavor = const String.fromEnvironment('FLUTTER_APP_FLAVOR'),
      adsMode = const String.fromEnvironment('ADS_MODE', defaultValue: 'test'),
      analytics = const String.fromEnvironment(
        'ANALYTICS',
        defaultValue: 'off',
      ),
      buildLabel = const String.fromEnvironment(
        'BUILD_LABEL',
        defaultValue: 'DEV',
      ),
      debugMenu = const String.fromEnvironment(
        'DEBUG_MENU',
        defaultValue: 'false',
      ),
      // Defaults are the Google test units (environments.md §4.1). Real
      // values are injected only by release.yml for prod.
      rewardedId = const String.fromEnvironment(
        'ADMOB_REWARDED_ID',
        defaultValue: 'ca-app-pub-$testAdPublisher/5224354917',
      ),
      interstitialId = const String.fromEnvironment(
        'ADMOB_INTERSTITIAL_ID',
        defaultValue: 'ca-app-pub-$testAdPublisher/1033173712',
      ),
      // Set by Flutter from --build-name / --build-number or pubspec.
      buildName = const String.fromEnvironment('FLUTTER_BUILD_NAME'),
      buildNumber = const String.fromEnvironment('FLUTTER_BUILD_NUMBER');

  /// `FLAVOR` from `config/<flavor>.json`.
  final String flavorName;

  /// The Gradle flavor the app was built with (`FLUTTER_APP_FLAVOR`); empty
  /// when built without `--flavor` (e.g. `flutter test`).
  final String appFlavor;

  /// `ADS_MODE`: `test` or `real`.
  final String adsMode;

  /// `ANALYTICS`: `off` or `on`.
  final String analytics;

  /// `BUILD_LABEL`: `DEV`, `BETA` or empty.
  final String buildLabel;

  /// `DEBUG_MENU`: `true` or `false`.
  final String debugMenu;

  /// `ADMOB_REWARDED_ID` (Android).
  final String rewardedId;

  /// `ADMOB_INTERSTITIAL_ID` (Android).
  final String interstitialId;

  /// `FLUTTER_BUILD_NAME`, e.g. `0.1.0`.
  final String buildName;

  /// `FLUTTER_BUILD_NUMBER`, e.g. `42`.
  final String buildNumber;

  /// The flavor from the config file.
  Flavor get flavor => parseFlavor(flavorName);

  /// True only when both the config file and the Gradle flavor say `prod`.
  /// A dev or beta APK built with the prod config (or the reverse) is
  /// treated as not prod (AD-3 belt and braces).
  bool get isProd => flavor == Flavor.prod && appFlavor == 'prod';

  /// The ad units this build shall use (AD-3, ENV-3).
  ///
  /// Real IDs are used only when all hold: the build is prod ([isProd]),
  /// `ADS_MODE` is `real`, the platform is Android (no iOS release exists),
  /// and the ID is a well-formed AdMob unit ID. In every other case the
  /// Google test unit is used, so dev and beta can never get a real ID even
  /// if one is passed in by mistake.
  AdUnitIds adUnitIds({required bool ios}) {
    final test = ios ? iosTestAdUnits : androidTestAdUnits;
    final realAllowed = isProd && adsMode == 'real' && !ios;
    String pick(String candidate, String testId) =>
        realAllowed && isWellFormedAdUnitId(candidate) ? candidate : testId;
    return AdUnitIds(
      rewarded: pick(rewardedId, test.rewarded),
      interstitial: pick(interstitialId, test.interstitial),
    );
  }

  /// Whether analytics may send events (AN-6): never in dev; in beta and
  /// prod only when the config turns it on and the Gradle flavor matches
  /// the config (no events from a mixed-up build).
  bool get analyticsEnabled =>
      flavor != Flavor.dev && appFlavor == flavorName && analytics == 'on';

  /// Whether the debug menu may be compiled in (ENV-9): dev only.
  bool get debugMenuEnabled => flavor == Flavor.dev && debugMenu == 'true';

  /// The Home build label (UI-2, amended in spec v3):
  /// dev "DEV · test ads" + version; beta "BETA X.Y.Z (N)"; prod none.
  String? get homeBuildLabel {
    final version = buildName.isEmpty
        ? ''
        : buildNumber.isEmpty
        ? buildName
        : '$buildName ($buildNumber)';
    switch (flavor) {
      case Flavor.prod:
        return null;
      case Flavor.beta:
        final label = buildLabel.isEmpty ? 'BETA' : buildLabel;
        return version.isEmpty ? label : '$label $version';
      case Flavor.dev:
        final label = buildLabel.isEmpty ? 'DEV' : buildLabel;
        return version.isEmpty
            ? '$label · test ads'
            : '$label · test ads · $version';
    }
  }
}

/// This build's environment.
const EnvConfig env = EnvConfig.fromEnvironment();
