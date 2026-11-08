# Publishing Carriage Rush: Horse Race on Google Play

Store title: **Carriage Rush: Horse Race** · launcher label: **Carriage Rush** · developer name: **MYAMANI**
Package: `com.myamani.carriagerush` (Android) · bundle ID `com.myamani.carriageRush` (iOS)

## Already done in the code
- AdMob: banner on menu + results, interstitial every 3rd race start (never during a race), game muted while an ad shows.
- Rewarded ad (opt-in): "Start from POLE • watch ad" on the menu and "Retry from POLE" on results — watch to the end to start 1st on the grid instead of 10th. No interstitial right after a rewarded ad.
- Google consent form (UMP) for EEA/UK users, plus a "Privacy settings" button on the menu when required.
- Release shrinking rules (`android/app/proguard-rules.pro`) — without them the release build crashes at launch.
- Release signing wired to `android/key.properties` (git-ignored).
- App name "Carriage Rush", INTERNET permission, AdMob app ID placeholder.

## Monetisation note
Google Play in-app purchases are not available to merchants in Morocco, so the game earns from AdMob only (AdMob pays out to Moroccan bank accounts once the balance reaches $100).

## 1. AdMob account (admob.google.com)
1. Add app → Android → "not published yet".
2. Copy the **App ID** (`ca-app-pub-XXXX~YYYY`).
3. Create three ad units: **Banner**, **Interstitial** and **Rewarded**; copy their IDs (`ca-app-pub-XXXX/ZZZZ`).
4. Privacy & messaging → create a **GDPR** message (and US states message) for the app, publish it.
5. Create `app-ads.txt` on a website you own and list it as the developer website in Play.

> Never tap your own real ads. Keep using the test IDs (the defaults) while developing.

## 2. Upload key (once — keep it safe forever)
```
keytool -genkey -v -keystore ~/upload-keystore-racers.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Then create `android/key.properties`:
```
storeFile=/Users/<you>/upload-keystore-racers.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

## 3. Build the bundle with the real IDs
```
flutter build appbundle --release \
  -PADMOB_APP_ID=ca-app-pub-XXXX~YYYY \
  --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-XXXX/BBBB \
  --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-XXXX/IIII \
  --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-XXXX/RRRR
```
Output: `build/app/outputs/bundle/release/app-release.aab`.
(Bump `version:` in `pubspec.yaml` for every upload, e.g. `1.0.1+2`.)

## 4. Play Console checklist
- [x] App icon 512×512 → `assets/icon/play_store_512.png`; feature graphic 1024×500 → `assets/icon/feature_graphic.png`.
  (Redraw: `flutter test tool/icon/render_icon_test.dart && dart run flutter_launcher_icons`.)
- [ ] At least 2 phone screenshots (portrait).
- [ ] Short + full description.
- [ ] **Privacy policy URL** (required because of ads). It must mention AdMob / advertising ID.
- [ ] Data safety form: collects Device or other IDs (advertising ID) via AdMob, for advertising; data encrypted in transit; no account.
- [ ] Content rating questionnaire (cartoon racing, no violence → expect Everyone / PEGI 3).
- [ ] Target audience: **13+** (choosing kids under 13 brings the Families policy and much stricter ad rules).
- [ ] "Contains ads": Yes.
- [ ] Closed testing: new personal developer accounts must run a closed test with **at least 12 testers for 14 days** before production access.

## Before you ship
- Play several races on a real Android phone (touch steering has only been tested on emulators/simulators).
- Try a low-end phone for frame rate.
- The package name `com.myamani.carriagerush` becomes permanent after the first upload.
- Name check (2026-11-08): no app titled "Carriage Rush" on Google Play or the App Store, no registered "Carriage Rush" trademark found. A lawyer / official registry search (OMPIC, EUIPO, USPTO) is the only definitive check.
