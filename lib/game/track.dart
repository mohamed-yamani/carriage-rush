import 'dart:math' as math;
import 'dart:typed_data';

import 'locations.dart';

/// World constants for the pseudo-3D road.
class World {
  static const double segmentLength = 200;
  static const double roadWidth = 2000; // half width of the road
  static const int lanes = 3;
  static const double cameraHeight = 1000;
  static const double cameraDepth = 0.84; // 1 / tan(fov / 2), ~100° fov
  static const int drawDistance = 260;
  static const int rumbleLength = 3;
  static const double playerZ = cameraHeight * cameraDepth;
  static const double maxSpeed = segmentLength * 60; // world units per second
  static const double unitsPerMeter = 180;
}

class ProjectedPoint {
  double worldX = 0, worldY = 0, worldZ = 0;
  double screenX = 0, screenY = 0, screenW = 0, scale = 0, cameraZ = 0;
}

enum SpriteKind { prop, banner, finish }

class RoadSprite {
  RoadSprite(this.kind, this.offset, {this.prop, this.seed = 0, this.height = 0, this.width = 0});
  final SpriteKind kind;
  final Prop? prop;
  final double offset; // in road half-widths, negative = left
  final int seed;
  final double height;
  final double width;
}

class Segment {
  Segment(this.index, double y1, double y2, this.curve) {
    p1
      ..worldY = y1
      ..worldZ = index * World.segmentLength;
    p2
      ..worldY = y2
      ..worldZ = (index + 1) * World.segmentLength;
    dark = (index ~/ World.rumbleLength).isOdd;
  }

  final int index;
  final double curve;
  final ProjectedPoint p1 = ProjectedPoint();
  final ProjectedPoint p2 = ProjectedPoint();
  final List<RoadSprite> sprites = [];
  late final bool dark;
  bool finishLine = false;
  double fog = 0;
  double clip = 0;
}

/// A point-to-point race course for one location: start grid, eased curves and hills, finish line,
/// then a run-off so the road keeps going past the line.
class Track {
  Track(this.location, {this.raceSegments = 3600}) : _rng = math.Random(location.seed) {
    _build();
    _buildGeometry();
  }

  final Location location;
  final int raceSegments;
  final math.Random _rng;
  final List<Segment> segments = [];
  static const startSegment = 20;

  double get length => segments.length * World.segmentLength;
  double get startZ => startSegment * World.segmentLength;
  double get finishZ => (startSegment + raceSegments) * World.segmentLength;
  double get raceLength => finishZ - startZ;

  double _lastY() => segments.isEmpty ? 0 : segments.last.p2.worldY;

  void _addSegment(double curve, double y) => segments.add(Segment(segments.length, _lastY(), y, curve));

  static double _easeIn(double a, double b, double p) => a + (b - a) * math.pow(p, 2);
  static double _easeInOut(double a, double b, double p) => a + (b - a) * ((-math.cos(p * math.pi) / 2) + 0.5);

  void _addRoad(int enter, int hold, int leave, double curve, double hill) {
    final startY = _lastY();
    final endY = startY + hill * World.segmentLength;
    final total = enter + hold + leave;
    for (var n = 0; n < enter; n++) {
      _addSegment(_easeIn(0, curve, n / enter), _easeInOut(startY, endY, n / total));
    }
    for (var n = 0; n < hold; n++) {
      _addSegment(curve, _easeInOut(startY, endY, (enter + n) / total));
    }
    for (var n = 0; n < leave; n++) {
      _addSegment(_easeInOut(curve, 0, n / leave), _easeInOut(startY, endY, (enter + hold + n) / total));
    }
  }

  void _build() {
    final loc = location;
    _addRoad(30, 50, 30, 0, 0); // straight start grid
    final target = startSegment + raceSegments + World.drawDistance + 50;
    while (segments.length < target) {
      final len = 20 + _rng.nextInt(45);
      final dir = _rng.nextBool() ? 1.0 : -1.0;
      final curve = switch (_rng.nextInt(5)) {
            0 => 0.0,
            1 || 2 => 2.0 * dir,
            3 => 4.0 * dir,
            _ => 6.0 * dir,
          } *
          loc.curviness;
      var hill = (_rng.nextDouble() - 0.5) * 60 * loc.hilliness;
      if (_lastY().abs() > 5000 * loc.hilliness) hill = -_lastY() / World.segmentLength * 0.7;
      _addRoad(len, len, len, curve, hill);
    }

    final finish = startSegment + raceSegments;
    for (var i = finish; i < finish + 3; i++) {
      segments[i].finishLine = true;
    }

    for (final s in segments) {
      if (s.index == startSegment + 2) s.sprites.add(RoadSprite(SpriteKind.finish, 0));
      if (s.index == finish) s.sprites.add(RoadSprite(SpriteKind.finish, 0));
      if (s.index == startSegment + 60 || (s.index > startSegment && (s.index - startSegment) % 700 == 0)) {
        s.sprites.add(RoadSprite(SpriteKind.banner, 0));
      }
      _dress(s);
    }
  }

  void _dress(Segment s) {
    final props = location.props;
    if (props.containsKey(Prop.lamp) && s.index % 8 == 0 && _rng.nextDouble() < props[Prop.lamp]!) {
      s.sprites
        ..add(RoadSprite(SpriteKind.prop, -1.25, prop: Prop.lamp))
        ..add(RoadSprite(SpriteKind.prop, 1.25, prop: Prop.lamp));
    }
    if (s.index % 4 != 0) return;
    for (final side in [-1.0, 1.0]) {
      for (final entry in props.entries) {
        final p = entry.key;
        if (p == Prop.lamp || _rng.nextDouble() >= entry.value * 0.6) continue;
        final near = switch (p) {
          Prop.building || Prop.kasbah => 2.2 + _rng.nextDouble() * 2.5,
          Prop.umbrella => 1.5 + _rng.nextDouble() * 1.2,
          _ => 1.35 + _rng.nextDouble() * 2.5,
        };
        final (h, w) = switch (p) {
          Prop.building => (2500 + _rng.nextDouble() * 6000, 1400 + _rng.nextDouble() * 1600),
          Prop.kasbah => (1800 + _rng.nextDouble() * 1800, 1800 + _rng.nextDouble() * 1400),
          Prop.palm => (2200 + _rng.nextDouble() * 1400, 1400.0),
          Prop.pine => (1600 + _rng.nextDouble() * 2000, 1000 + _rng.nextDouble() * 400),
          Prop.rock => (400 + _rng.nextDouble() * 900, 700 + _rng.nextDouble() * 1100),
          Prop.umbrella => (1100.0, 1100.0),
          Prop.lamp => (1900.0, 100.0),
        };
        s.sprites.add(RoadSprite(SpriteKind.prop, side * near,
            prop: p, seed: _rng.nextInt(1 << 30), height: h, width: w));
        break; // one prop per side per slot
      }
    }
  }

  Segment find(double z) {
    final i = (z / World.segmentLength).floor().clamp(0, segments.length - 1);
    return segments[i];
  }

  double curveAt(double z) => find(z).curve;

  // ---------- real 3D geometry (metres) ----------
  /// Centre line of the road at every segment boundary: position and heading (radians, 0 = +z, + = right).
  late final Float64List cx, cy, cz, heading;

  void _buildGeometry() {
    final n = segments.length + 1;
    cx = Float64List(n);
    cy = Float64List(n);
    cz = Float64List(n);
    heading = Float64List(n);
    for (var i = 0; i < segments.length; i++) {
      cy[i] = segments[i].p1.worldY * Geo.unitScale;
      final h = heading[i] + segments[i].curve * Geo.curveRate / 2;
      heading[i + 1] = heading[i] + segments[i].curve * Geo.curveRate;
      cx[i + 1] = cx[i] + math.sin(h) * Geo.segment;
      cz[i + 1] = cz[i] + math.cos(h) * Geo.segment;
    }
    cy[n - 1] = segments.last.p2.worldY * Geo.unitScale;
  }

  /// World pose of a point at track distance [z] (game units) and lateral offset [x] (road half-widths).
  Pose pose(double z, double x) {
    final f = (z / World.segmentLength).clamp(0.0, segments.length - 1e-6);
    final i = f.floor();
    final t = f - i;
    final h = heading[i] + (heading[i + 1] - heading[i]) * t;
    final px = cx[i] + (cx[i + 1] - cx[i]) * t;
    final py = cy[i] + (cy[i + 1] - cy[i]) * t;
    final pz = cz[i] + (cz[i + 1] - cz[i]) * t;
    final lat = x * Geo.halfWidth;
    final pitch = math.atan2(cy[i + 1] - cy[i], Geo.segment);
    return Pose(px + math.cos(h) * lat, py, pz - math.sin(h) * lat, h, pitch);
  }
}

/// Conversions between game units and metres for the 3D renderer.
class Geo {
  static const double segment = 2.0; // metres per track segment
  static const double halfWidth = 6.0; // metres from centre line to road edge (3 lanes of 4 m)
  static const double curveRate = 0.0025; // radians of heading change per segment per unit of curve
  static const double unitScale = segment / World.segmentLength;
}

class Pose {
  const Pose(this.x, this.y, this.z, this.heading, this.pitch);
  final double x, y, z, heading, pitch;
}
