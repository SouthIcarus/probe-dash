import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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
  bool _canRequestAds = false;

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
    if (!_canRequestAds) return;
    InterstitialAd.load(
      adUnitId: _interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (e) {
          debugPrint('Interstitial failed to load: $e');
          _interstitial = null;
          Future.delayed(const Duration(seconds: 30), _loadInterstitial);
        },
      ),
    );
  }

  /// Shows a rewarded ad. Completes with true only if the player watched
  /// it to the end (US-1: closing early grants nothing).
  Future<bool> showRewarded() {
    final ad = _rewarded;
    if (ad == null) return Future.value(false);
    _rewarded = null;
    final result = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (!result.isCompleted) result.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, e) {
        ad.dispose();
        _loadRewarded();
        if (!result.isCompleted) result.complete(false);
      },
    );
    ad.show(onUserEarnedReward: (_, _) => earned = true);
    return result.future;
  }

  /// Shows an interstitial if one is loaded. Completes when it closes.
  /// Returns whether one was shown.
  Future<bool> showInterstitial() {
    final ad = _interstitial;
    if (ad == null) return Future.value(false);
    _interstitial = null;
    final closed = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
        if (!closed.isCompleted) closed.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, e) {
        ad.dispose();
        _loadInterstitial();
        if (!closed.isCompleted) closed.complete(false);
      },
    );
    ad.show();
    return closed.future;
  }
}
