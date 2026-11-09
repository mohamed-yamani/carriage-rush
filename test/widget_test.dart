import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_racer/game/game.dart';
import 'package:night_racer/game/locations.dart';
import 'package:night_racer/game/track.dart';
import 'package:night_racer/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first launch asks for a name and country, then the menu starts a race', (tester) async {
    await tester.pumpWidget(const NightRacerApp());
    await tester.pump(const Duration(milliseconds: 100));
    // welcome card
    expect(find.text('WELCOME, RACER!'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'lucas');
    await tester.pump();
    // the country is pre-filled from the device region; open the picker to change it
    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pump(const Duration(milliseconds: 600)); // the scene behind keeps animating, so no pumpAndSettle
    await tester.enterText(find.byType(TextField).last, 'brazil');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Brazil'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text("LET'S RACE"));
    await tester.pump(const Duration(milliseconds: 200));
    // menu with the player's chip, no personal branding
    expect(find.text('LUCAS'), findsOneWidget);
    expect(find.text('CARRIAGE\nRUSH'), findsOneWidget);
    expect(find.textContaining('MYAMANI'), findsNothing);
    expect(find.text('PARIS'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('LONDON'), findsOneWidget);
    await tester.tap(find.text('RACE'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('BRAKE'), findsOneWidget);
    expect(find.text('POSITION'), findsOneWidget);
  });

  test('profile is saved and rivals come from around the world', () async {
    final g = Game();
    await g.setProfile(' Amélie ', 'FR');
    g.startRace();
    expect(g.player.name, 'AMÉLIE');
    expect(g.player.flag, '🇫🇷');
    final rivals = g.racers.where((r) => !r.isPlayer).toList();
    expect(rivals.length, 9);
    expect(rivals.map((r) => r.name).toSet().length, 9); // no duplicates
    expect(rivals.every((r) => r.flag.isNotEmpty), isTrue);
    expect(rivals.map((r) => r.country).toSet().length, greaterThan(4)); // a real mix
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('player_name'), 'AMÉLIE');
    expect(prefs.getString('player_country'), 'FR');
  });

  test('eight world courses, no personal branding', () {
    expect(locations.length, 8);
    expect(locations.map((l) => l.name), containsAll(['PARIS', 'LONDON', 'NEW YORK', 'TOKYO', 'DUBAI', 'SWISS ALPS', 'RIO', 'MARRAKECH']));
  });

  test('every location builds a course with a finish line', () {
    for (final loc in locations) {
      final t = Track(loc);
      expect(t.segments.length, greaterThan(Track.startSegment + t.raceSegments));
      expect(t.segments.any((s) => s.finishLine), isTrue);
    }
  });

  test('a full race: 10 cars, everyone moves, the player finishes with a place', () {
    final g = Game()..startRace();
    expect(g.racers.length, 10);
    expect(g.placeOf(g.player), 10); // starts at the back of the grid
    var steps = 0;
    while (g.phase != Phase.finished && steps < 60 * 400) {
      // simple autopilot: stay in the lane with the most room
      double ahead(double lane) => [
            ...g.racers.where((r) => !r.isPlayer).map((r) => (r.z, r.x)),
            ...g.traffic.map((t) => (t.z, t.x)),
          ].where((o) => (o.$2 - lane).abs() < 0.45 && o.$1 > g.player.z - 300).fold<double>(1e12, (m, o) => o.$1 < m ? o.$1 : m);
      final best = Game.lanes.reduce((a, b) => ahead(a) >= ahead(b) ? a : b);
      g.steerLeft = best < g.player.x - 0.1;
      g.steerRight = best > g.player.x + 0.1;
      g.update(1 / 60);
      steps++;
    }
    expect(g.phase, Phase.finished);
    expect(g.player.finishTime, isNotNull);
    final rows = g.results();
    expect(rows.length, 10);
    expect(g.racers.where((r) => !r.isPlayer).every((r) => r.z > g.track.startZ), isTrue);
    // ignore: avoid_print
    print('finished ${g.placeOf(g.player)}/10 in ${formatTime(g.player.finishTime!)}');
  });

  test('countdown beeps, GO neighs, finishing plays the fanfare', () {
    final g = Game()..startRace();
    expect(g.sounds, contains(Sfx.beep));
    g.sounds.clear();
    for (var i = 0; i < 60 * 4; i++) {
      g.update(1 / 60);
    }
    expect(g.sounds.where((s) => s == Sfx.beep).length, 2); // "2", "1"
    expect(g.sounds, containsAll([Sfx.go, Sfx.neigh]));
    g.player.z = g.track.finishZ - 10;
    g.update(1 / 60);
    expect(g.phase, Phase.finished);
    expect(g.sounds, contains(Sfx.fanfare));
  });

  test('driving into a roadside rock or tree is a crash with debris', () {
    // find a hittable prop on the Sahara course
    final g = Game()
      ..selectLocation(1)
      ..startRace();
    for (var i = 0; i < 60 * 4; i++) {
      g.update(1 / 60);
    }
    final t = g.track;
    final seg = t.segments.skip(200).firstWhere((s) => s.sprites.any((sp) =>
        sp.kind == SpriteKind.prop && sp.offset.abs() < 1.8 && sp.prop != Prop.kasbah && sp.prop != Prop.building));
    final prop = seg.sprites.firstWhere((sp) => sp.kind == SpriteKind.prop && sp.offset.abs() < 1.8);
    g.player
      ..z = seg.index * World.segmentLength
      ..x = prop.offset
      ..speed = World.maxSpeed * 0.8;
    g.sounds.clear();
    g.update(1 / 60);
    // you keep only part of your speed (how much depends on the difficulty)
    expect(g.player.speed, lessThan(World.maxSpeed * 0.8 * g.difficulty.hitKeep + 1));
    expect(g.sounds.any((s) => s == Sfx.rock || s == Sfx.crash), isTrue);
    expect(g.particles.length, greaterThan(10));
  });

  test('off-road kicks up dust and rumbles', () {
    final g = Game()..startRace();
    for (var i = 0; i < 60 * 4; i++) {
      g.update(1 / 60);
    }
    // move to a stretch with nothing on the verge to hit
    g.player
      ..x = 1.2
      ..speed = World.maxSpeed * 0.6;
    g.particles.clear();
    for (var i = 0; i < 20; i++) {
      g.player.x = 1.2;
      g.update(1 / 60);
    }
    expect(g.rumble, greaterThan(0.5));
    expect(g.particles, isNotEmpty);
  });

  test('pole start (rewarded perk) puts you at the front of the grid', () {
    final normal = Game()..startRace();
    expect(normal.placeOf(normal.player), 10);
    expect(normal.startedOnPole, isFalse);
    final pole = Game()..startRace(pole: true);
    expect(pole.placeOf(pole.player), 1);
    expect(pole.startedOnPole, isTrue);
    expect(pole.racers.length, 10);
  });

  test('difficulty: EASY by default, slower rivals than HARD, remembered', () async {
    final g = Game();
    expect(g.difficulty, Difficulty.easy);
    g.startRace();
    final easyTop = g.racers.where((r) => !r.isPlayer).map((r) => r.topSpeed).reduce((a, b) => a > b ? a : b);
    await g.setDifficulty(Difficulty.hard);
    g.startRace();
    final hardTop = g.racers.where((r) => !r.isPlayer).map((r) => r.topSpeed).reduce((a, b) => a > b ? a : b);
    expect(easyTop, lessThan(hardTop));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('difficulty'), 'hard');
  });

  /// Puts the player across the line in [place] (everyone else behind or ahead accordingly).
  void finishIn(Game g, int place) {
    for (var i = 0; i < 240; i++) {
      g.update(1 / 60);
    }
    final rivals = g.racers.where((r) => !r.isPlayer).toList();
    for (var i = 0; i < rivals.length; i++) {
      rivals[i].z = i < place - 1 ? g.track.finishZ + 100 : g.track.startZ + 1000; // place-1 rivals already done
      if (i < place - 1) rivals[i].finishTime = 0.001 * (i + 1); // crossed just before you
    }
    g.player.z = g.track.finishZ - 5;
    g.update(1 / 60);
  }

  test('winning pays coins + first-win bonus and puts you on pole next race', () async {
    final g = Game()..startRace();
    expect(g.placeOf(g.player), 10); // first race: from the back
    finishIn(g, 1);
    expect(g.phase, Phase.finished);
    expect(g.raceCoins, 100);
    expect(g.raceBonus, Game.firstWinBonus);
    expect(g.coins, 150);
    expect(g.medalFor(g.location.id), '🥇');
    g.startRace();
    expect(g.placeOf(g.player), 1); // won last time -> start 1st
    finishIn(g, 1);
    expect(g.raceBonus, 0); // the bonus is only for the first win in a city
    expect(g.coins, 250);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('coins'), 250);
  });

  test('finishing 5th starts you 5th; doubling coins works once', () {
    final g = Game()..startRace();
    finishIn(g, 5);
    expect(g.raceCoins, 25);
    g.doubleRaceCoins();
    g.doubleRaceCoins();
    expect(g.coins, 50);
    g.startRace();
    expect(g.placeOf(g.player), 5);
    g.startRace(pole: true);
    expect(g.placeOf(g.player), 1); // rewarded pole still wins
  });

  test('garage: buy with coins, select, and refuse when too poor', () async {
    final g = Game()..coins = 200;
    final (blue, bluePrice) = Game.paintChoices[1];
    expect(await g.chooseItem('paint', blue, bluePrice), isTrue);
    expect(g.coins, 200 - bluePrice);
    expect(g.paint, blue);
    expect(g.player.color, blue);
    final (cyan, cyanPrice) = Game.paintChoices.last;
    expect(await g.chooseItem('paint', cyan, cyanPrice), isFalse);
    expect(g.paint, blue);
    // owned items can be re-selected for free
    final (red, _) = Game.paintChoices.first;
    await g.chooseItem('paint', red, 0);
    expect(await g.chooseItem('paint', blue, bluePrice), isTrue);
    expect(g.coins, 200 - bluePrice);
  });
}
