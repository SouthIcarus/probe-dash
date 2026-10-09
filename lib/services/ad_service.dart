import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// How a rewarded ad ended (spec AD-6, US-1).
enum RewardedOutcome {
  /// Watched to the end: grant the reward.
  earned,

  /// Shown, then closed before the reward: no reward, but it was shown
  /// (counts for AD-6).
  closedEarly,

  /// The SDK couldn't show it: not shown (doesn't count for AD-6).
  failedToShow,

  /// No rewarded ad was loaded: nothing happened.
  notLoaded,
}

/// Rewarded and interstitial ads. Uses ONLY Google's public test ad units
/// (spec AD-3); swap in real IDs only right before store release.
class AdService {
  AdService({this.enabled = true});

  /// False in tests and on platforms without the ads plugin.
  final bool enabled;

  // Google's documented test ad units. Safe to tap; never earn money.
  static String get _rewardedId => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/1712485313'
      : 'ca-app-pub-3940256099942544/5224354917';
  static String get _interstitialId => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/4411468910'
      : 'ca-app-pub-3940256099942544/1033173712';

  RewardedAd? _rewardedAd;
  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;
  bool _canRequestAds = false;

  /// Started when the interstitial finishes loading. Monotonic, so a device
  /// clock change can't make an old ad look fresh (AD-7).
  final Stopwatch _interstitialLoadedFor = Stopwatch();

  /// How long the loaded interstitial has been loaded, or null if none is
  /// loaded (AD-7: older than 1 h counts as not loaded).
  Duration? get interstitialAge =>
      _interstitial == null ? null : _interstitialLoadedFor.elapsed;

  final ValueNotifier<bool> _rewardedReady = ValueNotifier(false);

  RewardedAd? get _rewarded => _rewardedAd;
  set _rewarded(RewardedAd? ad) {
    _rewardedAd = ad;
    _rewardedReady.value = ad != null;
  }

  /// Whether a rewarded ad is loaded, as a listenable so ad buttons switch
  /// from "No ad available" to active as soon as one finishes loading
  /// (A-09).
  ValueListenable<bool> get rewardedReadyListenable => _rewardedReady;

  bool get rewardedReady => rewardedReadyListenable.value;

  /// Runs the consent flow (AD-2: EEA/UK users see Google's consent form),
  /// then starts the SDK and preloads ads.
  Future<void> init() async {
    if (!enabled) return;
    try {
      final done = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => ConsentForm.loadAndShowConsentFormIfRequired((_) {
          if (!done.isCompleted) done.complete();
        }),
        (_) {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future;
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
      if (!_canRequestAds) return;
      await MobileAds.instance.initialize();
      _loadRewarded();
      _loadInterstitial();
    } catch (e) {
      debugPrint('Ads unavailable: $e');
    }
  }

  void _loadRewarded() {
    if (!_canRequestAds) return;
    RewardedAd.load(
      adUnitId: _rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (e) {
          debugPrint('Rewarded failed to load: $e');
          _rewarded = null;
          Future.delayed(const Duration(seconds: 30), _loadRewarded);
        },
      ),
    );
  }

  void _loadInterstitial() {
    if (!_canRequestAds || _loadingInterstitial || _interstitial != null) {
      return; // never two loads at once, never over a loaded ad
    }
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: _interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
          _interstitialLoadedFor
            ..reset()
            ..start();
        },
        onAdFailedToLoad: (e) {
          debugPrint('Interstitial failed to load: $e');
          _loadingInterstitial = false;
          _interstitial = null;
          Future.delayed(const Duration(seconds: 30), _loadInterstitial);
        },
      ),
    );
  }

  /// Loads an interstitial for a later run if none is loaded or loading
  /// (AD-7: preload; never waited for).
  void requestInterstitialLoad() => _loadInterstitial();

  /// Drops a loaded interstitial that is too old to show (AD-7) and loads a
  /// fresh one.
  void discardStaleInterstitial() {
    final ad = _interstitial;
    _interstitial = null;
    _interstitialLoadedFor
      ..stop()
      ..reset();
    ad?.dispose();
    _loadInterstitial();
  }

  /// Shows a rewarded ad and reports how it ended. The reward is granted
  /// only for [RewardedOutcome.earned] (US-1: closing early grants
  /// nothing). [RewardedOutcome.closedEarly] still means the ad was shown
  /// (AD-6), unlike [RewardedOutcome.failedToShow].
  Future<RewardedOutcome> showRewarded() {
    final ad = _rewarded;
    if (ad == null) return Future.value(RewardedOutcome.notLoaded);
    _rewarded = null;
    final result = Completer<RewardedOutcome>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (!result.isCompleted) {
          result.complete(
              earned ? RewardedOutcome.earned : RewardedOutcome.closedEarly);
        }
      },
      onAdFailedToShowFullScreenContent: (ad, e) {
        ad.dispose();
        _loadRewarded();
        if (!result.isCompleted) result.complete(RewardedOutcome.failedToShow);
      },
    );
    ad.show(onUserEarnedReward: (_, _) => earned = true);
    return result.future;
  }

  /// Asks the SDK to show the loaded interstitial and returns at once.
  /// Returns false (and calls nothing) if none is loaded.
  ///
  /// - [onShown]: the ad is on screen (`onAdShowedFullScreenContent`, AD-9).
  /// - [onFailed]: the SDK couldn't show it.
  /// - [onDismissed]: the player closed it (close button or back inside it).
  ///
  /// The SDK can't cancel a show once requested, so the callbacks stay
  /// attached until the ad is dismissed or fails: a late ad is still
  /// reported. The ad is disposed only then (disposing earlier would drop
  /// its later callbacks), and the next one is loaded (AD-7).
  bool showInterstitial({
    required VoidCallback onShown,
    required VoidCallback onFailed,
    required VoidCallback onDismissed,
  }) {
    final ad = _interstitial;
    if (ad == null) return false;
    _interstitial = null;
    _interstitialLoadedFor
      ..stop()
      ..reset();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => onShown(),
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
        onDismissed();
      },
      onAdFailedToShowFullScreenContent: (ad, e) {
        debugPrint('Interstitial failed to show: $e');
        ad.dispose();
        _loadInterstitial();
        onFailed();
      },
    );
    ad.show();
    return true;
  }
}
