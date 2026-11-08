import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob ad unit IDs. Defaults are Google's official *test* units, which are safe to click.
/// Release builds pass the real ones in:
///   flutter build appbundle --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-xxx/yyy \
///                           --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-xxx/zzz
class AdIds {
  static String get banner => Platform.isAndroid
      ? const String.fromEnvironment('ADMOB_BANNER_ANDROID', defaultValue: 'ca-app-pub-3940256099942544/9214589741')
      : const String.fromEnvironment('ADMOB_BANNER_IOS', defaultValue: 'ca-app-pub-3940256099942544/2435281174');

  static String get rewarded => Platform.isAndroid
      ? const String.fromEnvironment('ADMOB_REWARDED_ANDROID', defaultValue: 'ca-app-pub-3940256099942544/5224354917')
      : const String.fromEnvironment('ADMOB_REWARDED_IOS', defaultValue: 'ca-app-pub-3940256099942544/1712485313');

  static String get interstitial => Platform.isAndroid
      ? const String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID',
          defaultValue: 'ca-app-pub-3940256099942544/1033173712')
      : const String.fromEnvironment('ADMOB_INTERSTITIAL_IOS', defaultValue: 'ca-app-pub-3940256099942544/4411468910');
}

/// Consent (UMP), SDK start-up and the between-races interstitial.
///
/// Ad placement rules for a racing game: never during a race. A banner sits on the menu and
/// results screens; a full-screen ad shows at most once every [racesPerInterstitial] races,
/// right when the player taps to race again.
class Ads {
  Ads._();
  static final Ads instance = Ads._();

  static const racesPerInterstitial = 3;

  /// Ads are off in `flutter test` and on platforms AdMob does not support.
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS) && !Platform.environment.containsKey('FLUTTER_TEST');

  final ValueNotifier<bool> ready = ValueNotifier(false); // consent done + SDK started
  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier(false);
  final ValueNotifier<bool> rewardedReady = ValueNotifier(false); // drives the "watch ad" buttons
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  int _racesSinceAd = 0;
  bool _starting = false;

  /// Ask for consent where the law requires it (EEA/UK/Switzerland), then start the SDK.
  Future<void> init() async {
    if (!supported || _starting) return;
    _starting = true;
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(tagForUnderAgeOfConsent: false),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) debugPrint('consent form: ${error.message}');
        });
        done.complete();
      },
      (error) {
        debugPrint('consent info: ${error.message}');
        done.complete(); // carry on: canRequestAds() decides below
      },
    );
    await done.future;
    final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
    privacyOptionsRequired.value = status == PrivacyOptionsRequirementStatus.required;
    if (!await ConsentInformation.instance.canRequestAds()) return;
    await MobileAds.instance.initialize();
    ready.value = true;
    _loadInterstitial();
    _loadRewarded();
  }

  /// "Privacy settings" button for users who must be able to change their consent.
  Future<void> showPrivacyOptions() async {
    await ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) debugPrint('privacy options: ${error.message}');
    });
  }

  void _loadInterstitial() {
    if (!ready.value) return;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (e) {
          debugPrint('interstitial failed: ${e.message}');
          _interstitial = null;
        },
      ),
    );
  }

  void _loadRewarded() {
    if (!ready.value) return;
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          rewardedReady.value = true;
        },
        onAdFailedToLoad: (e) {
          debugPrint('rewarded failed: ${e.message}');
          _rewarded = null;
          rewardedReady.value = false;
          // try again a little later rather than hammering the network
          Future.delayed(const Duration(seconds: 30), _loadRewarded);
        },
      ),
    );
  }

  /// Opt-in rewarded ad. [onReward] runs only if the player watched it to the end; [onClose] always runs
  /// once the ad is gone, after [onReward]. Watching one also resets the interstitial counter,
  /// so the player never gets two ads back to back.
  void showRewarded({required VoidCallback onReward, VoidCallback? onShow, VoidCallback? onClose}) {
    final ad = _rewarded;
    if (ad == null) return;
    _rewarded = null;
    rewardedReady.value = false;
    var earned = false;
    void finish(Ad ad) {
      ad.dispose();
      onClose?.call();
      if (earned) {
        _racesSinceAd = 0;
        onReward();
      }
      _loadRewarded();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => onShow?.call(),
      onAdDismissedFullScreenContent: finish,
      onAdFailedToShowFullScreenContent: (ad, e) => finish(ad),
    );
    ad.show(onUserEarnedReward: (_, _) => earned = true);
  }

  /// Call when the player starts another race. Shows an interstitial every few races,
  /// then runs [then] once it is closed (or straight away if there is nothing to show).
  /// [onShow]/[onClose] let the game mute itself while the ad is up.
  void betweenRaces(VoidCallback then, {VoidCallback? onShow, VoidCallback? onClose}) {
    _racesSinceAd++;
    final ad = _interstitial;
    if (ad == null || _racesSinceAd < racesPerInterstitial) {
      then();
      return;
    }
    _racesSinceAd = 0;
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => onShow?.call(),
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        onClose?.call();
        then();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, e) {
        ad.dispose();
        onClose?.call();
        then();
        _loadInterstitial();
      },
    );
    ad.show();
  }
}

/// Adaptive banner that sizes itself to the screen width. Renders nothing until an ad has loaded,
/// so layouts never jump around for players who see no ads.
class BannerAdBox extends StatefulWidget {
  const BannerAdBox({super.key});

  @override
  State<BannerAdBox> createState() => _BannerAdBoxState();
}

class _BannerAdBoxState extends State<BannerAdBox> {
  BannerAd? _ad;
  bool _loaded = false;
  int? _width;

  @override
  void initState() {
    super.initState();
    Ads.instance.ready.addListener(_maybeLoad);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _width = MediaQuery.sizeOf(context).width.truncate();
    _maybeLoad();
  }

  Future<void> _maybeLoad() async {
    if (!Ads.instance.ready.value || _ad != null || _width == null) return;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(_width!);
    if (size == null || !mounted) return;
    final ad = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, e) {
          debugPrint('banner failed: ${e.message}');
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    Ads.instance.ready.removeListener(_maybeLoad);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
