# Carriage Rush: Horse Race

A 3D horse-and-carriage racing game for Android and iOS, built with Flutter — **without a game engine**.
Race 9 rivals through four Moroccan places, from the cobbled streets of Casablanca at midnight to the dunes of the Sahara.

<p>
  <img src="docs/screenshots/menu.jpg" width="180" alt="Menu">
  <img src="docs/screenshots/casablanca.jpg" width="180" alt="Casablanca at night">
  <img src="docs/screenshots/sahara.jpg" width="180" alt="Sahara sunset">
  <img src="docs/screenshots/atlas.jpg" width="180" alt="Atlas mountains">
  <img src="docs/screenshots/agadir.jpg" width="180" alt="Agadir coast">
</p>

## Features
- **You vs 9 AI rivals** — start last, finish first. Rivals change lanes, overtake and trade paint.
- **4 places**: Casablanca (night, cobblestones), Sahara (sunset, sand track, kasbahs), Atlas (snow, gravel pass), Agadir (ocean promenade).
- **Galloping horses** with animated legs, spoked carriage wheels, coachmen, lanterns at night.
- **Effects**: dust and sand off-road, debris when you hit rocks or palms, camera shake, haptics.
- **Sound**: hooves synced to your horse's cadence, the pack around you, crashes, whip cracks, fanfare, per-place ambience.
- **Touch controls**: hold the left/right half of the screen to steer, hold BRAKE to slow down.
- Best time and best place saved per course.
- **AdMob**: banner on menus, interstitial every 3rd race (never mid-race), opt-in rewarded ad to start from pole.

## How it works
- **Custom software 3D renderer** (`lib/game/painter3d.dart`): low-poly meshes are transformed, near-plane clipped, flat-shaded, fogged and depth-sorted every frame, then drawn in a few `Canvas.drawVertices` calls. Roughly 5–15k triangles in 2–6 ms.
- **Procedural models** (`lib/game/meshes.dart`): horses (8 gallop frames), carriages, carts, palms, pines, kasbahs, lamps, gantries.
- **Procedural tracks** (`lib/game/track.dart`): eased curves and hills turned into a real 3D centre line.
- **Synthesised audio** (`tool/make_sounds.py`): every sound effect is generated with numpy — no samples, no licensing.
- **Code-drawn artwork** (`tool/icon/render_icon_test.dart`): app icon, adaptive icon layers and Play feature graphic.

## Run it
```bash
flutter pub get
flutter run
```
Handy flags for testing:
```bash
flutter run --dart-define=AUTOSTART=true --dart-define=LOCATION=1   # jump straight into a race (0-3 = place)
flutter run --dart-define=SHOWFPS=true                               # frame time + triangle count
```

## Tests
```bash
flutter test test/widget_test.dart   # UI, race rules, sounds, collisions
flutter test test/balance_sim.dart   # an autopilot races every course and prints the result
```

## Regenerate assets
```bash
python3 tool/make_sounds.py                                   # sounds -> assets/sfx/
flutter test tool/icon/render_icon_test.dart && dart run flutter_launcher_icons   # icons
```

## Release
See [RELEASE.md](RELEASE.md) for AdMob setup, signing and the Google Play checklist.
Real ad unit IDs are passed at build time with `--dart-define`; the repo only contains Google's public test IDs.

---
Made by **MYAMANI**.
