import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'countries.dart';
import 'locations.dart';
import 'track.dart';

enum Phase { menu, countdown, racing, paused, finished }

/// How hard the rivals push and how much a mistake costs.
enum Difficulty {
  easy('EASY', rivalPace: 0.85, traffic: 0.5, crashKeep: 0.6, hitKeep: 0.65, leaderBrake: 0.85),
  normal('NORMAL', rivalPace: 0.95, traffic: 0.8, crashKeep: 0.4, hitKeep: 0.45, leaderBrake: 0.93),
  hard('HARD', rivalPace: 0.99, traffic: 1.0, crashKeep: 0.3, hitKeep: 0.35, leaderBrake: 0.95);

  const Difficulty(this.label,
      {required this.rivalPace, required this.traffic, required this.crashKeep, required this.hitKeep, required this.leaderBrake});
  final String label;
  final double rivalPace; // fastest rival's top speed as a share of yours
  final double traffic; // share of the slow carts left on the road
  final double crashKeep; // speed you keep after hitting a cart
  final double hitKeep; // speed you keep after hitting a rock/tree/lamp
  final double leaderBrake; // how much rivals far ahead of you ease off
}

/// One-shot sounds the game asks for; the screen's sound engine plays them.
enum Sfx { beep, go, neigh, crash, bump, rock, fanfare, click, whip }

/// A bit of dust, sand, gravel or debris flying around in world space (metres).
class Particle {
  Particle(this.x, this.y, this.z, this.vx, this.vy, this.vz, this.life, this.color, this.size,
      {this.gravity = 0, this.grow = 0, this.floor = -1e9});
  double x, y, z, vx, vy, vz, life;
  final int color;
  double size;
  final double gravity, grow, floor;
  late final double maxLife = life;
}

class Racer {
  Racer(this.name, this.color, {this.isPlayer = false, this.topSpeed = World.maxSpeed, this.country = ''});
  final String name;
  final String country; // ISO code, for the flag
  String get flag => country.isEmpty ? '' : flagOf(country);
  final int color;
  final bool isPlayer;
  double topSpeed;
  double z = 0, x = 0, targetX = 0, speed = 0;
  double? finishTime;
  double bumpCooldown = 0;
  bool aheadOfPlayer = true;
  double gait = 0; // gallop phase, cycles per second grow with speed
  int coat = 0xFF6B4226; // horse colour
}

class TrafficCar {
  TrafficCar(this.z, this.x, this.speed, this.color);
  double z;
  final double x;
  double speed;
  final int color;
  double gait = 0;
}

class ResultRow {
  ResultRow(this.racer, this.time, this.estimated);
  final Racer racer;
  final double time;
  final bool estimated;
}

/// All game state and rules. The painter reads from it; the screen feeds input into it.
class Game extends ChangeNotifier {
  Game() {
    selectLocation(0);
    _loadBests();
  }

  static const rivalColors = [
    0xFF3D8BFF, 0xFFFFC23D, 0xFF33D17A, 0xFFB86BFF, 0xFFEDEDED, 0xFFFF8A3D, 0xFF00C2C7, 0xFF8C5A3C, 0xFF6B7280,
  ];
  static const trafficColors = [0xFF9AA0A6, 0xFF5F6B7A, 0xFFB8A27A, 0xFF7A8F6B];
  static const coats = [0xFF6B4226, 0xFF2A2420, 0xFFE8E2D6, 0xFF9C5B2E, 0xFF8A8580, 0xFFC9A36B];
  static const playerColor = 0xFFFF2D55;
  static const lanes = [-0.6, 0.0, 0.6];

  final math.Random _rng = math.Random();

  int locationIndex = 0;
  Location get location => locations[locationIndex];
  late Track track;

  Phase phase = Phase.menu;
  late Racer player;
  List<Racer> racers = [];
  List<TrafficCar> traffic = [];
  double skyOffset = 0, time = 0, raceTime = 0, countdown = 0;
  double camHeading = 0; // chase camera direction, lags behind the road a little
  double visualSteer = 0; // -1..1, how much the car body leans/yaws into the steering
  double shake = 0, crashFlash = 0;
  int bestPlaceThisRace = 10;
  bool newBest = false;
  bool startedOnPole = false;
  final Map<String, double> bestTimes = {};
  final Map<String, int> bestPlaces = {};

  // player profile (asked for on first launch, editable from the menu)
  String playerName = 'YOU';
  String playerCountry = '';
  bool hasProfile = false;
  bool profileLoaded = false;

  Future<void> setProfile(String name, String country) async {
    playerName = name.trim().toUpperCase();
    playerCountry = country;
    hasProfile = true;
    player = _newPlayer()..z = player.z;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player_name', playerName);
    await prefs.setString('player_country', playerCountry);
  }

  Racer _newPlayer() => Racer(playerName, playerColor, isPlayer: true, country: playerCountry);

  // input
  bool steerLeft = false, steerRight = false, braking = false;

  // effects
  final List<Sfx> sounds = []; // drained by the sound engine every frame
  final List<Particle> particles = [];
  bool muted = false;
  Difficulty difficulty = Difficulty.easy;

  Future<void> setDifficulty(Difficulty d) async {
    difficulty = d;
    sfx(Sfx.click);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('difficulty', d.name);
  }
  bool adShowing = false; // full-screen ad up: the game goes quiet
  double rumble = 0; // 0..1 off-road shaking
  double _hitCooldown = 0, _hapticTimer = 0;

  void sfx(Sfx s) => sounds.add(s);

  /// How many rivals are galloping close to you (drives the pack sound).
  int get nearbyRivals =>
      racers.where((r) => !r.isPlayer && (r.z - player.z).abs() < World.segmentLength * 25).length;

  Future<void> toggleMute() async {
    muted = !muted;
    sfx(Sfx.click);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('muted', muted);
  }

  double get position => player.z - World.playerZ; // camera z
  double get speedPercent => player.speed / World.maxSpeed;
  int get kmh => (speedPercent * 72).round(); // a racing horse tops out around 70 km/h
  bool get offRoad => player.x.abs() > 1.0;
  double progressOf(Racer r) => ((r.z - track.startZ) / track.raceLength).clamp(0.0, 1.0);

  // ---------- persistence ----------
  Future<void> _loadBests() async {
    final prefs = await SharedPreferences.getInstance();
    muted = prefs.getBool('muted') ?? false;
    final d = prefs.getString('difficulty');
    difficulty = Difficulty.values.firstWhere((x) => x.name == d, orElse: () => difficulty);
    final name = prefs.getString('player_name');
    // a profile chosen during this session always wins over the stored one
    if (!hasProfile && name != null && name.isNotEmpty) {
      playerName = name;
      playerCountry = prefs.getString('player_country') ?? '';
      hasProfile = true;
      if (phase == Phase.menu) player = _newPlayer()..z = player.z;
    }
    profileLoaded = true;
    for (final l in locations) {
      final t = prefs.getDouble('best_time_${l.id}');
      final p = prefs.getInt('best_place_${l.id}');
      if (t != null) bestTimes[l.id] = t;
      if (p != null) bestPlaces[l.id] = p;
    }
    notifyListeners();
  }

  Future<void> _saveBests() async {
    final prefs = await SharedPreferences.getInstance();
    final id = location.id;
    if (bestTimes[id] != null) await prefs.setDouble('best_time_$id', bestTimes[id]!);
    if (bestPlaces[id] != null) await prefs.setInt('best_place_$id', bestPlaces[id]!);
  }

  // ---------- setup ----------
  void selectLocation(int i) {
    locationIndex = i % locations.length;
    track = Track(location);
    player = _newPlayer()..z = track.startZ;
    racers = [];
    traffic = [];
    phase = Phase.menu;
    _snapCamera();
    notifyListeners();
  }

  /// [pole] puts you at the front of the grid instead of the back (the rewarded-ad perk).
  void startRace({bool pole = false}) {
    track = Track(location);
    player = _newPlayer();
    racers = [];
    // nine rivals from around the world, a different mix every race
    final pool = rivalPool.where((r) => r.$1 != playerName).toList()..shuffle(_rng);
    for (var i = 0; i < 9; i++) {
      // rivals are not equal: the front of the grid is quicker
      final top = World.maxSpeed * (difficulty.rivalPace - i * 0.011 + _rng.nextDouble() * 0.02);
      racers.add(Racer(pool[i].$1, rivalColors[i], topSpeed: top, country: pool[i].$2)
        ..coat = coats[i % coats.length]
        ..gait = _rng.nextDouble());
    }
    player.coat = 0xFFF2EEE6; // white horse, easy to spot from behind
    if (pole) {
      racers.insert(0, player);
    } else {
      racers.add(player);
    }
    startedOnPole = pole;
    // two-wide grid behind the start line, player starts at the back (or on pole)
    for (var slot = 0; slot < racers.length; slot++) {
      final r = racers[slot];
      final row = slot ~/ 2;
      r
        ..z = track.startZ - row * 3.5 * World.segmentLength
        ..x = slot.isEven ? -0.35 : 0.35
        ..targetX = r.x
        ..speed = 0
        ..finishTime = null;
    }
    traffic = [];
    final count = (location.traffic * 6 * difficulty.traffic).round();
    for (var i = 0; i < count; i++) {
      final z = track.startZ + World.segmentLength * 120 + _rng.nextDouble() * (track.raceLength - World.segmentLength * 150);
      traffic.add(TrafficCar(z, lanes[_rng.nextInt(3)], World.maxSpeed * (0.28 + _rng.nextDouble() * 0.12),
          trafficColors[_rng.nextInt(trafficColors.length)]));
    }
    raceTime = 0;
    countdown = 3.0;
    shake = crashFlash = rumble = 0;
    particles.clear();
    newBest = false;
    phase = Phase.countdown;
    sfx(Sfx.beep);
    _snapCamera();
    notifyListeners();
  }

  void togglePause() {
    if (phase == Phase.racing) {
      phase = Phase.paused;
    } else if (phase == Phase.paused) {
      phase = Phase.racing;
    }
    notifyListeners();
  }

  void toMenu() => selectLocation(locationIndex);

  // ---------- standings ----------
  int placeOf(Racer r) => standings().indexOf(r) + 1;

  List<Racer> standings() {
    final list = [...racers];
    list.sort((a, b) {
      if (a.finishTime != null && b.finishTime != null) return a.finishTime!.compareTo(b.finishTime!);
      if (a.finishTime != null) return -1;
      if (b.finishTime != null) return 1;
      return b.z.compareTo(a.z);
    });
    return list;
  }

  List<ResultRow> results() {
    return standings().map((r) {
      if (r.finishTime != null) return ResultRow(r, r.finishTime!, false);
      final remaining = math.max(0.0, track.finishZ - r.z);
      final est = raceTime + remaining / math.max(r.speed, World.maxSpeed * 0.5);
      return ResultRow(r, est, true);
    }).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  // ---------- simulation ----------
  void update(double dt) {
    time += dt;
    switch (phase) {
      case Phase.menu:
        // attract mode: cruise down the selected course behind the menu
        player.speed = World.maxSpeed * 0.35;
        player.z += player.speed * dt;
        player.gait += dt * strideRate(player.speed);
        if (player.z > track.finishZ) {
          player.z = track.startZ;
          _snapCamera();
        }
        skyOffset += 0.001 * track.curveAt(player.z) * 0.35;
      case Phase.countdown:
        final before = countdown.ceil();
        countdown -= dt;
        if (countdown <= 0) {
          phase = Phase.racing;
          sfx(Sfx.go);
          sfx(Sfx.neigh);
          HapticFeedback.mediumImpact();
        } else if (countdown.ceil() < before) {
          sfx(Sfx.beep);
        }
      case Phase.paused:
        break;
      case Phase.racing || Phase.finished:
        if (phase == Phase.racing) raceTime += dt;
        _updatePlayer(dt);
        for (final r in racers) {
          if (!r.isPlayer) _updateRival(r, dt);
        }
        _updateTraffic(dt);
        for (final r in racers) {
          r.gait += dt * strideRate(r.speed);
        }
        _collisions();
        _propHits();
        _overtakes();
        _checkFinish();
        _offRoadEffects(dt);
    }
    _updateParticles(dt);
    shake = math.max(0, shake - dt);
    crashFlash = math.max(0, crashFlash - dt);
    final steer = phase == Phase.racing ? (steerRight ? 1.0 : 0.0) - (steerLeft ? 1.0 : 0.0) : 0.0;
    visualSteer += (steer - visualSteer) * math.min(1, dt * 6);
    final target = track.pose(player.z, player.x).heading + visualSteer * 0.05;
    camHeading += (target - camHeading) * math.min(1, dt * 4);
    notifyListeners();
  }

  void _snapCamera() {
    camHeading = track.pose(player.z, player.x).heading;
    visualSteer = 0;
  }

  void _updatePlayer(double dt) {
    final p = player;
    final sp = speedPercent;
    final curve = track.curveAt(p.z);
    if (p.finishTime != null) {
      // cool-down lap after the line
      p.speed += (World.maxSpeed * 0.4 - p.speed) * math.min(1, dt * 1.5);
      p.x += (0 - p.x) * math.min(1, dt * 2);
    } else {
      final step = dt * 2.2 * sp;
      if (steerLeft) p.x -= step;
      if (steerRight) p.x += step;
      p.x -= step * sp * curve * 0.09; // curves push you outwards (always weaker than full steering)
      p.x = p.x.clamp(-1.9, 1.9);
      if (braking) {
        p.speed -= World.maxSpeed * 1.2 * dt;
      } else {
        p.speed += World.maxSpeed / 4.5 * dt * (1 - 0.5 * sp); // auto throttle
      }
      if (offRoad && p.speed > World.maxSpeed / 4) p.speed -= World.maxSpeed * 0.9 * dt;
      p.speed = p.speed.clamp(0, p.topSpeed);
    }
    p.z += p.speed * dt;
    p.bumpCooldown = math.max(0, p.bumpCooldown - dt);
    skyOffset += 0.001 * curve * sp;
  }

  Iterable<({double z, double x, double speed})> _obstacles(Racer self) sync* {
    for (final r in racers) {
      if (!identical(r, self)) yield (z: r.z, x: r.x, speed: r.speed);
    }
    for (final t in traffic) {
      yield (z: t.z, x: t.x, speed: t.speed);
    }
  }

  void _updateRival(Racer r, double dt) {
    const seg = World.segmentLength;
    var desired = r.topSpeed;
    if (r.finishTime != null) {
      desired = World.maxSpeed * 0.4;
    } else {
      // gentle rubber band so the pack stays around you
      final gap = (r.z - player.z) / seg;
      if (gap > 40) desired *= difficulty.leaderBrake;
      if (gap < -40) desired *= 1.04;
      if (track.curveAt(r.z).abs() > 4) desired *= 0.96;
    }

    // look ahead for anything slower in our lane
    ({double z, double x, double speed})? blocker;
    for (final o in _obstacles(r)) {
      final dz = o.z - r.z;
      if (dz > 0 && dz < seg * 10 && (o.x - r.x).abs() < 0.45 && o.speed < r.speed + 50) {
        if (blocker == null || dz < blocker.z - r.z) blocker = o;
      }
    }
    if (blocker != null) {
      double? best;
      for (final lane in lanes) {
        var free = true;
        for (final o in _obstacles(r)) {
          final dz = o.z - r.z;
          if (dz > -seg * 2 && dz < seg * 12 && (o.x - lane).abs() < 0.45) {
            free = false;
            break;
          }
        }
        if (free && (best == null || (lane - r.x).abs() < (best - r.x).abs())) best = lane;
      }
      if (best != null) {
        r.targetX = best;
      } else {
        desired = math.min(desired, blocker.speed);
      }
    }

    final accel = desired > r.speed ? World.maxSpeed / 4.5 : World.maxSpeed * 1.2;
    r.speed += (desired - r.speed).clamp(-accel * dt, accel * dt);
    r.x += (r.targetX - r.x).clamp(-1.1 * dt, 1.1 * dt);
    r.z += r.speed * dt;
    r.bumpCooldown = math.max(0, r.bumpCooldown - dt);
  }

  void _updateTraffic(double dt) {
    for (final t in traffic) {
      t.z += t.speed * dt;
      t.gait += dt * 1.1;
    }
  }

  /// Gallop cadence: ~1 stride/s at a walk up to ~2.6 strides/s flat out.
  static double strideRate(double speed) => speed <= 1 ? 0 : 0.9 + 1.7 * (speed / World.maxSpeed);

  void _collisions() {
    const seg = World.segmentLength;
    final p = player;
    // you vs rivals: bump and trade paint, nobody is out of the race
    for (final r in racers) {
      if (r.isPlayer || p.bumpCooldown > 0) continue;
      final dz = r.z - p.z, dx = r.x - p.x;
      if (dz.abs() < seg * 1.5 && dx.abs() < 0.42) {
        if (dz > 0) {
          p.speed = math.min(p.speed, r.speed * 0.85);
        } else {
          r.speed *= 0.8;
        }
        final push = dx >= 0 ? 1.0 : -1.0;
        p.x -= push * 0.12;
        r.targetX = (r.x + push * 0.5).clamp(-0.6, 0.6);
        p.bumpCooldown = 0.5;
        shake = math.max(shake, 0.25);
        sfx(Sfx.bump);
        _burst(r.z, (p.x + r.x) / 2, 1.0, 8, const [0xFF6A4628, 0xFFD9A93A], 3);
        HapticFeedback.mediumImpact();
      }
    }
    // anyone vs slow traffic: a real crash
    for (final t in traffic) {
      for (final r in racers) {
        if ((t.z - r.z).abs() < seg * 1.6 && (t.x - r.x).abs() < 0.42) {
          r.speed *= r.isPlayer ? difficulty.crashKeep : 0.5;
          final hitZ = t.z;
          t.z += seg * 10; // knocked out of the way
          if (r.isPlayer) {
            shake = 0.5;
            crashFlash = 0.5;
            sfx(Sfx.crash);
            // hay and splinters everywhere
            _burst(hitZ, t.x, 1.2, 30, const [0xFFE3C15A, 0xFFD4AE48, 0xFF8A5A32], 5);
            HapticFeedback.heavyImpact();
          }
        }
      }
    }
  }

  void _checkFinish() {
    for (final r in racers) {
      if (r.finishTime == null && r.z >= track.finishZ) {
        r.finishTime = raceTime;
        if (r.isPlayer) _playerFinished();
      }
    }
  }

  void _playerFinished() {
    phase = Phase.finished;
    sfx(Sfx.fanfare);
    HapticFeedback.heavyImpact();
    final id = location.id;
    final place = placeOf(player);
    bestPlaceThisRace = place;
    final t = player.finishTime!;
    if (bestTimes[id] == null || t < bestTimes[id]!) {
      bestTimes[id] = t;
      newBest = true;
    }
    if (bestPlaces[id] == null || place < bestPlaces[id]!) bestPlaces[id] = place;
    _saveBests();
  }
}

// ---------- effects ----------
extension GameEffects on Game {
  /// Hitbox half-width (road half-widths) of a roadside prop, or null if it is too far out to hit.
  static double? _propRadius(RoadSprite sp) => switch (sp.prop) {
        Prop.rock => sp.width * 0.0025 / Geo.halfWidth * 0.6,
        Prop.lamp => 0.05,
        Prop.palm || Prop.pine => 0.07,
        Prop.umbrella => 0.06,
        _ => null,
      };

  static List<int> _debrisColors(Prop p, Location loc) => switch (p) {
        Prop.rock => loc.far == FarLayer.mountains
            ? const [0xFF7D8494, 0xFF5F6675, 0xFFA9A49C]
            : const [0xFFB0683E, 0xFF8E4A2C, 0xFFD9925A],
        Prop.palm => const [0xFF2E8B3E, 0xFF7A5230, 0xFF237331],
        Prop.pine => const [0xFF1E5A3A, 0xFFE9F0F7, 0xFF5A3A22],
        Prop.lamp => const [0xFFFFE08A, 0xFFFFF6D0, 0xFF5E606C],
        Prop.umbrella => const [0xFFFF4D4D, 0xFFFFFFFF, 0xFF2F8CFF],
        _ => const [0xFF888888],
      };

  void _propHits() {
    final p = player;
    _hitCooldown = math.max(0, _hitCooldown - 1 / 60);
    if (p.x.abs() < 1.05 || _hitCooldown > 0 || p.finishTime != null) return;
    final i = (p.z / World.segmentLength).floor();
    for (var k = i - 1; k <= i + 1; k++) {
      if (k < 0 || k >= track.segments.length) continue;
      for (final sp in track.segments[k].sprites) {
        if (sp.kind != SpriteKind.prop) continue;
        final r = _propRadius(sp);
        if (r == null || (sp.offset - p.x).abs() > r + 0.16) continue;
        // smack: big slowdown, bounce back toward the road, debris
        p.speed *= difficulty.hitKeep;
        p.x -= p.x.sign * 0.18;
        shake = 0.45;
        crashFlash = 0.3;
        _hitCooldown = 0.8;
        sfx(sp.prop == Prop.rock ? Sfx.rock : Sfx.crash);
        _burst(k * World.segmentLength, sp.offset, sp.prop == Prop.rock ? 0.6 : 1.5, 28,
            _debrisColors(sp.prop!, location), 6);
        HapticFeedback.heavyImpact();
        return;
      }
    }
  }

  void _overtakes() {
    for (final r in racers) {
      if (r.isPlayer) continue;
      final ahead = r.z > player.z;
      if (r.aheadOfPlayer && !ahead && player.finishTime == null) sfx(Sfx.whip);
      r.aheadOfPlayer = ahead;
    }
  }

  void _offRoadEffects(double dt) {
    final p = player;
    final moving = p.speed > World.maxSpeed * 0.08;
    final off = offRoad && moving;
    rumble += ((off ? 1.0 : 0.0) - rumble) * math.min(1, dt * 8);
    final rig = track.pose(p.z - 1.5 / Geo.unitScale, p.x);
    final sh = math.sin(rig.heading), ch = math.cos(rig.heading);
    final rnd = _rngFx;
    if (off) {
      // thick dust from both rear wheels
      for (var n = 0; n < 4; n++) {
        final side = n.isEven ? 0.9 : -0.9;
        final wx = rig.x + ch * side - sh * 1.0, wz = rig.z - sh * side - ch * 1.0;
        particles.add(Particle(wx, rig.y + 0.3, wz, (rnd.nextDouble() - 0.5) * 2 - sh * 2, 0.8 + rnd.nextDouble() * 1.5,
            (rnd.nextDouble() - 0.5) * 2 - ch * 2, 0.8 + rnd.nextDouble() * 0.6, _dustColor, 0.7,
            grow: 2.8));
      }
      _hapticTimer -= dt;
      if (_hapticTimer <= 0) {
        HapticFeedback.selectionClick();
        _hapticTimer = 0.12;
      }
    } else if (moving && location.road != RoadStyle.cobble && location.road != RoadStyle.paving) {
      // a light trail of dust on sand and gravel tracks
      if (rnd.nextDouble() < 0.5 * speedPercent) {
        final wx = rig.x - sh * 1.2, wz = rig.z - ch * 1.2;
        particles.add(Particle(wx + (rnd.nextDouble() - 0.5) * 1.6, rig.y + 0.2, wz, 0, 0.4 + rnd.nextDouble() * 0.6, 0,
            0.6, _dustColor, 0.3,
            grow: 1.2));
      }
    }
  }

  /// Dust is a paler version of the ground so it reads against it.
  int get _dustColor => Color.lerp(location.dust, const Color(0xFFFFFFFF), 0.45)!.toARGB32();

  /// Debris burst at track distance [z], lateral [x] (road units), [height] metres up.
  void _burst(double z, double x, double height, int count, List<int> colors, double power) {
    final at = track.pose(z, x);
    final rnd = _rngFx;
    for (var n = 0; n < count; n++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final sp = power * (0.4 + rnd.nextDouble() * 0.8);
      particles.add(Particle(at.x, at.y + height, at.z, math.cos(a) * sp, 2 + rnd.nextDouble() * power,
          math.sin(a) * sp, 0.8 + rnd.nextDouble() * 0.6, colors[n % colors.length], 0.12 + rnd.nextDouble() * 0.12,
          gravity: 12,
          floor: at.y + 0.05));
    }
  }

  void _updateParticles(double dt) {
    for (final q in particles) {
      q.vy -= q.gravity * dt;
      final drag = q.gravity > 0 ? 1.0 : math.exp(-dt * 2.5);
      q.vx *= drag;
      q.vz *= drag;
      q.x += q.vx * dt;
      q.y += q.vy * dt;
      q.z += q.vz * dt;
      q.size += q.grow * dt;
      q.life -= dt;
      if (q.y < q.floor) {
        // land and bounce a little
        q.y = q.floor;
        q.vy = -q.vy * 0.3;
        q.vx *= 0.5;
        q.vz *= 0.5;
      }
    }
    particles.removeWhere((q) => q.life <= 0);
    if (particles.length > 400) particles.removeRange(0, particles.length - 400);
  }

  static final math.Random _rngFx = math.Random();
}

String formatTime(double t) {
  final m = t ~/ 60;
  final s = t - m * 60;
  return '$m:${s.toStringAsFixed(2).padLeft(5, '0')}';
}
