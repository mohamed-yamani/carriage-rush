// Balance check: an autopilot races every location at every difficulty. Run with: flutter test test/balance_sim.dart
// ignore_for_file: avoid_print
import 'package:night_racer/game/game.dart';
import 'package:night_racer/game/locations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  SharedPreferences.setMockInitialValues({});
  for (final diff in Difficulty.values) {
    for (var li = 0; li < locations.length; li++) {
      final g = Game()
        ..selectLocation(li)
        ..difficulty = diff
        ..startRace();
      var bumps = 0, crashes = 0, steps = 0;
      var lastCool = 0.0;
      while (g.phase != Phase.finished && steps < 60 * 400) {
        double ahead(double lane) => [
              ...g.racers.where((r) => !r.isPlayer).map((r) => (r.z, r.x)),
              ...g.traffic.map((t) => (t.z, t.x)),
            ].where((o) => (o.$2 - lane).abs() < 0.45 && o.$1 > g.player.z - 300).fold<double>(
                1e12, (m, o) => o.$1 < m ? o.$1 : m);
        final best = Game.lanes.reduce((a, b) => ahead(a) >= ahead(b) ? a : b);
        g.steerLeft = best < g.player.x - 0.1;
        g.steerRight = best > g.player.x + 0.1;
        final hadFlash = g.crashFlash;
        g.update(1 / 60);
        if (g.player.bumpCooldown > lastCool) bumps++;
        lastCool = g.player.bumpCooldown;
        if (g.crashFlash > hadFlash) crashes++;
        steps++;
      }
      final rows = g.results();
      final mine = rows.firstWhere((r) => r.racer.isPlayer).time;
      print('${diff.label.padRight(6)} ${g.location.name.padRight(10)} place ${g.placeOf(g.player).toString().padLeft(2)}'
          '  you ${formatTime(mine)}  winner ${formatTime(rows.first.time)}'
          '  margin ${(rows[1].time - rows[0].time).toStringAsFixed(1)}s  bumps $bumps crashes $crashes');
    }
  }
}
