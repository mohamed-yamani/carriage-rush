import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'game.dart';
import 'locations.dart';
import 'meshes.dart';
import 'track.dart';

/// A tiny software 3D engine on top of Canvas.drawVertices: flat-shaded low-poly meshes,
/// near-plane clipping, distance fog and painter's-algorithm depth sorting.
class RacePainter extends CustomPainter {
  RacePainter(this.game) : super(repaint: game);

  final Game game;

  // ---- per-frame triangle buffers (reused) ----
  static const _cap = 40000;
  static final _pos = Float32List(_cap * 6);
  static final _col = Int32List(_cap * 3);
  static final _depth = Float64List(_cap + 256);
  static int _n = 0;
  static final _specials = <_Special>[];
  static final _tags = <_Tag>[];

  // ---- camera ----
  late double _w, _h, _cx, _cy, _f;
  late double _camX, _camY, _camZ;
  late double _rx, _ry, _rz, _ux, _uy, _uz, _fx, _fy, _fz;
  late double _heading;
  static const _near = 0.35;
  static const _far = 440.0;

  // ---- lighting ----
  late Location _loc;
  late double _lx, _ly, _lz, _amb, _dif, _fogStart;
  late int _fog;

  static final _stars = List.generate(160, (i) {
    final r = math.Random(i * 7919);
    return Offset(r.nextDouble() * math.pi * 2, r.nextDouble());
  });
  static TextPainter _label(String text, Color color, {double size = 100, double spacing = 18}) => TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w900, letterSpacing: spacing)),
        textDirection: TextDirection.ltr,
      )..layout();
  /// The sign text is rasterised once; drawing glyphs through a perspective matrix would blow up
  /// the shared glyph atlas when the sign gets close and corrupt every other piece of text.
  static final ui.Image _bannerImage = () {
    final tp = _label('CARRIAGE RUSH', const Color(0xFFFFD447));
    final rec = ui.PictureRecorder();
    tp.paint(Canvas(rec), Offset.zero);
    return rec.endRecording().toImageSync(tp.width.ceil(), tp.height.ceil());
  }();
  static final _nameTags = <String, TextPainter>{};

  /// Last paint time in ms (shown with --dart-define=SHOWFPS=true).
  static double lastPaintMs = 0;
  static int lastTriangles = 0;

  @override
  void paint(Canvas canvas, Size size) {
    final sw = Stopwatch()..start();
    _w = size.width;
    _h = size.height;
    _cx = _w / 2;
    _cy = _h * 0.42;
    _f = (_h / 2) / math.tan(36 * math.pi / 180);
    _loc = game.location;
    _setupCamera();
    _setupLighting();

    canvas.save();
    if (game.shake > 0 || game.rumble > 0.05) {
      final s = game.shake * 18 + game.rumble * 5;
      final r = math.Random((game.time * 1000).floor());
      canvas.translate((r.nextDouble() - 0.5) * s, (r.nextDouble() - 0.5) * s);
    }
    final horizon = _horizonY();
    _drawSky(canvas, horizon);
    final ground = Rect.fromLTRB(-20, horizon, _w + 20, _h + 20);
    canvas.drawRect(
      ground,
      Paint()
        ..shader = ui.Gradient.linear(ground.topCenter, Offset(0, horizon + _h * 0.12),
            [Color(_fog), _loc.groundDark]),
    );

    _n = 0;
    _specials.clear();
    _tags.clear();
    _buildRoad();
    _buildProps();
    _buildCars();
    _buildParticles();
    _flush(canvas);
    _drawTags(canvas);
    canvas.restore();

    if (game.crashFlash > 0) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = const Color(0xFFFF2040).withValues(alpha: game.crashFlash * 0.45));
    }
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(rect.center, size.longestSide * 0.75,
            [Colors.transparent, Colors.black.withValues(alpha: _loc.night ? 0.5 : 0.25)], [0.55, 1]),
    );
    lastPaintMs = sw.elapsedMicroseconds / 1000;
    lastTriangles = _n;
  }

  // ---------- camera ----------
  void _setupCamera() {
    final p = game.track.pose(game.player.z, game.player.x);
    _heading = game.camHeading;
    final sh = math.sin(_heading), ch = math.cos(_heading);
    final back = game.phase == Phase.menu ? 10.0 : 9.5;
    final up = game.phase == Phase.menu ? 4.0 : 5.8;
    _camX = p.x - sh * back;
    _camZ = p.z - ch * back;
    // keep the camera above the road even when cresting hills
    final behind = game.track.pose(game.player.z - back / Geo.unitScale, game.player.x);
    _camY = math.max(p.y, behind.y) + up;
    final tx = p.x + sh * 14, ty = p.y + 0.4, tz = p.z + ch * 14;
    var fx = tx - _camX, fy = ty - _camY, fz = tz - _camZ;
    final fl = math.sqrt(fx * fx + fy * fy + fz * fz);
    fx /= fl;
    fy /= fl;
    fz /= fl;
    // right = up x forward, up = forward x right
    var rx = fz, rz = -fx;
    final rl = math.sqrt(rx * rx + rz * rz);
    rx /= rl;
    rz /= rl;
    _rx = rx;
    _ry = 0;
    _rz = rz;
    _ux = fy * rz - fz * 0;
    _uy = fz * rx - fx * rz;
    _uz = fx * 0 - fy * rx;
    _fx = fx;
    _fy = fy;
    _fz = fz;
  }

  double _horizonY() {
    // a far point straight ahead at camera height
    final dx = math.sin(_heading) * 10000, dz = math.cos(_heading) * 10000;
    final yc = dx * _ux + dz * _uz, zc = dx * _fx + dz * _fz;
    return _cy - _f * yc / zc;
  }

  void _setupLighting() {
    _fog = _loc.fog.toARGB32();
    if (_loc.night) {
      _lx = 0.3;
      _ly = 0.85;
      _lz = -0.4;
      _amb = 0.42;
      _dif = 0.32;
      _fogStart = 30;
    } else {
      _lx = -0.45;
      _ly = 0.75;
      _lz = -0.5;
      _amb = 0.55;
      _dif = 0.55;
      _fogStart = 70;
    }
    final l = math.sqrt(_lx * _lx + _ly * _ly + _lz * _lz);
    _lx /= l;
    _ly /= l;
    _lz /= l;
  }

  int _fogMix(int c, double depth) {
    var t = (depth - _fogStart) / (_far - _fogStart);
    if (t <= 0) return c;
    if (t > 1) t = 1;
    t = math.pow(t, 0.8).toDouble();
    final r = ((c >> 16) & 0xFF) + ((((_fog >> 16) & 0xFF) - ((c >> 16) & 0xFF)) * t);
    final g = ((c >> 8) & 0xFF) + ((((_fog >> 8) & 0xFF) - ((c >> 8) & 0xFF)) * t);
    final b = (c & 0xFF) + (((_fog & 0xFF) - (c & 0xFF)) * t);
    return 0xFF000000 | (r.round() << 16) | (g.round() << 8) | b.round();
  }

  // ---------- triangle emission ----------
  final _cxs = Float64List(3), _cys = Float64List(3), _czs = Float64List(3);
  final _clipX = Float64List(4), _clipY = Float64List(4), _clipZ = Float64List(4);

  /// World-space triangle -> camera space -> clipped, projected, stored with depth (+[bias] sorts it further back).
  void _emit(double ax, double ay, double az, double bx, double by, double bz, double cx, double cy, double cz,
      int color, double bias) {
    if (_n >= _cap - 2) return;
    final xs = _cxs, ys = _cys, zs = _czs;
    _toCam(0, ax, ay, az);
    _toCam(1, bx, by, bz);
    _toCam(2, cx, cy, cz);
    final inside = (zs[0] >= _near ? 1 : 0) + (zs[1] >= _near ? 1 : 0) + (zs[2] >= _near ? 1 : 0);
    if (inside == 0) return;
    final depth = (zs[0] + zs[1] + zs[2]) / 3;
    if (depth > _far + 40) return;
    final col = _fogMix(color, depth);
    if (inside == 3) {
      _store(xs[0], ys[0], zs[0], xs[1], ys[1], zs[1], xs[2], ys[2], zs[2], col, depth + bias);
      return;
    }
    // clip against the near plane (Sutherland–Hodgman, single plane)
    var k = 0;
    for (var i = 0; i < 3; i++) {
      final j = (i + 1) % 3;
      final ai = zs[i] >= _near, bj = zs[j] >= _near;
      if (ai) {
        _clipX[k] = xs[i];
        _clipY[k] = ys[i];
        _clipZ[k] = zs[i];
        k++;
      }
      if (ai != bj) {
        final t = (_near - zs[i]) / (zs[j] - zs[i]);
        _clipX[k] = xs[i] + (xs[j] - xs[i]) * t;
        _clipY[k] = ys[i] + (ys[j] - ys[i]) * t;
        _clipZ[k] = _near;
        k++;
      }
    }
    final d = math.max(depth, _near) + bias;
    _store(_clipX[0], _clipY[0], _clipZ[0], _clipX[1], _clipY[1], _clipZ[1], _clipX[2], _clipY[2], _clipZ[2], col, d);
    if (k == 4) {
      _store(_clipX[0], _clipY[0], _clipZ[0], _clipX[2], _clipY[2], _clipZ[2], _clipX[3], _clipY[3], _clipZ[3], col, d);
    }
  }

  void _toCam(int i, double x, double y, double z) {
    final dx = x - _camX, dy = y - _camY, dz = z - _camZ;
    _cxs[i] = dx * _rx + dy * _ry + dz * _rz;
    _cys[i] = dx * _ux + dy * _uy + dz * _uz;
    _czs[i] = dx * _fx + dy * _fy + dz * _fz;
  }

  void _store(double x0, double y0, double z0, double x1, double y1, double z1, double x2, double y2, double z2,
      int col, double depth) {
    final o = _n * 6;
    _pos[o] = _cx + _f * x0 / z0;
    _pos[o + 1] = _cy - _f * y0 / z0;
    _pos[o + 2] = _cx + _f * x1 / z1;
    _pos[o + 3] = _cy - _f * y1 / z1;
    _pos[o + 4] = _cx + _f * x2 / z2;
    _pos[o + 5] = _cy - _f * y2 / z2;
    final c = _n * 3;
    _col[c] = col;
    _col[c + 1] = col;
    _col[c + 2] = col;
    _depth[_n] = depth;
    _n++;
  }

  /// Camera-space depth of a world point (for culling and specials).
  double _depthOf(double x, double y, double z) => (x - _camX) * _fx + (y - _camY) * _fy + (z - _camZ) * _fz;

  Offset? _project(double x, double y, double z) {
    final dx = x - _camX, dy = y - _camY, dz = z - _camZ;
    final zc = dx * _fx + dy * _fy + dz * _fz;
    if (zc < _near) return null;
    return Offset(_cx + _f * (dx * _rx + dz * _rz) / zc, _cy - _f * (dx * _ux + dy * _uy + dz * _uz) / zc);
  }

  /// Is a sphere (world centre, radius) possibly on screen?
  bool _visible(double x, double y, double z, double radius) {
    final dx = x - _camX, dy = y - _camY, dz = z - _camZ;
    final zc = dx * _fx + dy * _fy + dz * _fz;
    if (zc < -radius || zc > _far + radius) return false;
    final xc = dx * _rx + dz * _rz;
    return xc.abs() < (zc + radius) * (_cx / _f) + radius * 1.5;
  }

  void _emitMesh(Mesh m, double px, double py, double pz,
      {double yaw = 0, double pitch = 0, double roll = 0, double sx = 1, double sy = 1, double sz = 1,
      int body = 0xFFFFFFFF, int coat = 0xFF6B4226, int tint = 0xFFFFFFFF, double bias = 0}) {
    // R = Ry(yaw) * Rx(pitch) * Rz(roll)
    final cyw = math.cos(yaw), syw = math.sin(yaw);
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final cr = math.cos(roll), sr = math.sin(roll);
    // Rz then Rx then Ry, expanded into a 3x3 matrix
    final m00 = cyw * cr + syw * sp * sr, m01 = -cyw * sr + syw * sp * cr, m02 = syw * cp;
    final m10 = cp * sr, m11 = cp * cr, m12 = -sp;
    final m20 = -syw * cr + cyw * sp * sr, m21 = syw * sr + cyw * sp * cr, m22 = cyw * cp;
    final bodyDark = shade(body, 0.5);
    final coatDark = shade(coat, 0.45);
    final v = m.v, nn = m.n;
    for (var t = 0; t < m.count; t++) {
      final o = t * 9;
      final ax0 = v[o] * sx, ay0 = v[o + 1] * sy, az0 = v[o + 2] * sz;
      final bx0 = v[o + 3] * sx, by0 = v[o + 4] * sy, bz0 = v[o + 5] * sz;
      final cx0 = v[o + 6] * sx, cy0 = v[o + 7] * sy, cz0 = v[o + 8] * sz;
      final ax = px + m00 * ax0 + m01 * ay0 + m02 * az0;
      final ay = py + m10 * ax0 + m11 * ay0 + m12 * az0;
      final az = pz + m20 * ax0 + m21 * ay0 + m22 * az0;
      final bx = px + m00 * bx0 + m01 * by0 + m02 * bz0;
      final by = py + m10 * bx0 + m11 * by0 + m12 * bz0;
      final bz = pz + m20 * bx0 + m21 * by0 + m22 * bz0;
      final cx = px + m00 * cx0 + m01 * cy0 + m02 * cz0;
      final cy = py + m10 * cx0 + m11 * cy0 + m12 * cz0;
      final cz = pz + m20 * cx0 + m21 * cy0 + m22 * cz0;
      final n0 = nn[t * 3], n1 = nn[t * 3 + 1], n2 = nn[t * 3 + 2];
      final nx = m00 * n0 + m01 * n1 + m02 * n2;
      final ny = m10 * n0 + m11 * n1 + m12 * n2;
      final nz = m20 * n0 + m21 * n1 + m22 * n2;
      final flags = m.f[t];
      final mx = (ax + bx + cx) / 3 - _camX, my = (ay + by + cy) / 3 - _camY, mz = (az + bz + cz) / 3 - _camZ;
      final facing = nx * mx + ny * my + nz * mz;
      if ((flags & kTwoSided) == 0 && facing > 0) continue; // back face
      var c = m.c[t];
      if (c == kBody) {
        c = body;
      } else if (c == kBodyDark) {
        c = bodyDark;
      } else if (c == kCoat) {
        c = coat;
      } else if (c == kCoatDark) {
        c = coatDark;
      } else if (c == 0xFFFFFFFF && tint != 0xFFFFFFFF) {
        c = tint;
      }
      if ((flags & kEmissive) == 0) {
        var l = nx * _lx + ny * _ly + nz * _lz;
        if ((flags & kTwoSided) != 0 && facing > 0) l = -l;
        c = shade(c, _amb + _dif * math.max(0, l));
      } else if (!_loc.night) {
        c = shade(c, 0.85); // lights look dimmer in daylight
      }
      _emit(ax, ay, az, bx, by, bz, cx, cy, cz, c, (flags & kDecal) != 0 ? bias - 0.25 : bias);
    }
  }

  // ---------- world ----------
  void _buildRoad() {
    final track = game.track;
    final segs = track.segments;
    final ps = (game.player.z / World.segmentLength).floor();
    final start = math.max(0, ps - 6);
    final end = math.min(segs.length - 1, ps + 220);
    final pp = track.pose(game.player.z, game.player.x);
    final pf = math.sin(pp.heading), pfz = math.cos(pp.heading);
    final groundK = _amb + _dif * _ly;
    final headlights = _loc.night && game.phase != Phase.menu;

    var i = start;
    while (i < end) {
      final step = (i - ps) > 70 ? 2 : 1;
      final j = math.min(i + step, segs.length);
      final seg = segs[i];
      final x0 = track.cx[i], y0 = track.cy[i], z0 = track.cz[i];
      final x1 = track.cx[j], y1 = track.cy[j], z1 = track.cz[j];
      final r0x = math.cos(track.heading[i]), r0z = -math.sin(track.heading[i]);
      final r1x = math.cos(track.heading[j]), r1z = -math.sin(track.heading[j]);

      void strip(double a, double b, int color, double bias, [double lift = 0]) {
        final ax = x0 + r0x * a, az = z0 + r0z * a, bx = x0 + r0x * b, bz = z0 + r0z * b;
        final cx = x1 + r1x * b, cz = z1 + r1z * b, dx = x1 + r1x * a, dz = z1 + r1z * a;
        _emit(ax, y0 + lift, az, bx, y0 + lift, bz, cx, y1 + lift, cz, color, bias);
        _emit(ax, y0 + lift, az, cx, y1 + lift, cz, dx, y1 + lift, dz, color, bias);
      }

      // light pools: street lamps at night, and your headlights
      var boost = 1.0;
      if (_loc.night && _loc.props.containsKey(Prop.lamp) && (i % 8 <= 1 || i % 8 == 7)) boost = 1.45;
      double roadBoost(double lane) {
        if (!headlights) return boost;
        final mx = (x0 + r0x * lane) - pp.x, mz = (z0 + r0z * lane) - pp.z;
        final d = mx * pf + mz * pfz, l = (mx * pfz - mz * pf).abs();
        if (d < 1 || d > 45 || l > 2 + d * 0.22) return boost;
        return boost + 0.9 * math.exp(-d / 20);
      }

      final g = shade(seg.dark ? _loc.groundDark.toARGB32() : _loc.groundLight.toARGB32(), groundK / 0.9 * boost);
      strip(-90, -24, g, 2.4);
      strip(-24, -6.7, g, 2.2);
      strip(6.7, 24, g, 2.2);
      strip(24, 90, g, 2.4);
      // raised stone curbs instead of painted rumble strips
      final curb = shade((seg.dark ? _loc.rumbleA : _loc.rumbleB).toARGB32(), groundK / 0.9 * boost);
      const curbH = 0.18;
      strip(-6.7, -6, curb, 1.7, curbH);
      strip(6, 6.7, curb, 1.7, curbH);
      final near = i - ps < 60;
      if (near) {
        final face = shade(curb, 0.75);
        for (final x in const [-6.0, 6.0]) {
          final ax = x0 + r0x * x, az = z0 + r0z * x, bx = x1 + r1x * x, bz = z1 + r1z * x;
          _emit(ax, y0, az, bx, y1, bz, bx, y1 + curbH, bz, face, 1.65);
          _emit(ax, y0, az, bx, y1 + curbH, bz, ax, y0 + curbH, az, face, 1.65);
        }
      }

      // the road surface itself, styled for horses and carriages
      final light = _loc.roadLight.toARGB32(), dark = _loc.roadDark.toARGB32();
      final k = groundK / 0.9;
      double hash(int a, int b) => (((a * 73856093) ^ (b * 19349663)) & 0xFFFF) / 65535.0;
      void tiles(List<double> edges, int Function(int col) colorOf) {
        for (var c = 0; c + 1 < edges.length; c++) {
          final a = edges[c], b = edges[c + 1];
          strip(a, b, shade(colorOf(c), k * roadBoost((a + b) / 2)), 1.6);
        }
      }

      if (!near) {
        tiles(const [-6.0, -2.0, 2.0, 6.0], (_) => seg.dark ? dark : light);
      } else {
        switch (_loc.road) {
          case RoadStyle.cobble:
            // staggered setts: every other row shifted by half a stone
            final shift = i.isOdd ? 0.75 : 0.0;
            final edges = <double>[-6.0];
            for (var x = -6.0 + 1.5 - shift; x < 6.0 - 0.01; x += 1.5) {
              if (x > -6.0 + 0.01) edges.add(x);
            }
            edges.add(6.0);
            tiles(edges, (c) => shade(light, 0.78 + 0.34 * hash(i, c)));
          case RoadStyle.paving:
            tiles(const [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0],
                (c) => shade((c + i).isEven ? light : dark, 0.95 + 0.1 * hash(i, c)));
          case RoadStyle.sand || RoadStyle.gravel:
            final speckle = _loc.road == RoadStyle.gravel ? 0.3 : 0.12;
            tiles(const [-6.0, -3.0, 0.0, 3.0, 6.0],
                (c) => shade(seg.dark ? dark : light, 1 - speckle / 2 + speckle * hash(i, c)));
            // wheel ruts worn into the track where the carriages run
            final rut = shade(dark, k * 0.88);
            for (final lane in const [-3.6, 0.0, 3.6]) {
              strip(lane - 1.0, lane - 0.8, rut, 1.5, 0.005);
              strip(lane + 0.8, lane + 1.0, rut, 1.5, 0.005);
            }
        }
      }
      if (seg.finishLine) {
        for (var c = 0; c < 10; c++) {
          if ((c + i).isEven) continue;
          strip(-6 + c * 1.2, -6 + (c + 1) * 1.2, shade(0xFFFFFFFF, k), 1.5, 0.01);
        }
      }
      i = j;
    }
  }

  void _buildProps() {
    final track = game.track;
    final segs = track.segments;
    final ps = (game.player.z / World.segmentLength).floor();
    final end = math.min(segs.length - 1, ps + 180);
    final rockTint = (_loc.far == FarLayer.mountains ? const Color(0xFF7D8494) : const Color(0xFFB0683E)).toARGB32();
    for (var i = math.max(0, ps - 4); i < end; i++) {
      for (final sp in segs[i].sprites) {
        final z = i * World.segmentLength;
        switch (sp.kind) {
          case SpriteKind.banner || SpriteKind.finish:
            final p = track.pose(z, 0);
            if (!_visible(p.x, p.y + 6, p.z, 10)) continue;
            final mesh = sp.kind == SpriteKind.finish ? Models.finishGantry : Models.signGantry;
            _emitMesh(mesh, p.x, p.y, p.z, yaw: p.heading);
            if (sp.kind == SpriteKind.banner) _addBannerText(p);
          case SpriteKind.prop:
            final prop = sp.prop!;
            final side = sp.offset < 0 ? -1.0 : 1.0;
            final rng = sp.seed;
            switch (prop) {
              case Prop.building:
                final w = sp.width * 0.008, h = sp.height * 0.006;
                final p = track.pose(z, side * (sp.offset.abs() + 1.5 + w / 2 / Geo.halfWidth));
                if (!_visible(p.x, p.y + h / 2, p.z, h)) continue;
                _emitMesh(Models.building[rng % 3], p.x, p.y, p.z,
                    yaw: p.heading, sx: w, sy: h, sz: w,
                    body: _loc.buildingColor.toARGB32(), coat: _loc.windowColor.toARGB32());
              case Prop.kasbah:
                final w = sp.width * 0.007, h = sp.height * 0.006;
                final p = track.pose(z, side * (sp.offset.abs() + w / 2 / Geo.halfWidth));
                if (!_visible(p.x, p.y + h / 2, p.z, w)) continue;
                _emitMesh(Models.kasbah, p.x, p.y, p.z, yaw: p.heading, sx: w, sy: h, sz: w);
              case Prop.lamp:
                final p = track.pose(z, sp.offset);
                if (!_visible(p.x, p.y + 5, p.z, 6)) continue;
                // arm points at the road
                final yaw = p.heading + (side < 0 ? math.pi : 0);
                _emitMesh(Models.lamp, p.x, p.y, p.z, yaw: yaw);
                if (_loc.night) {
                  final hx = p.x + math.cos(yaw) * -1.7, hz = p.z - math.sin(yaw) * -1.7;
                  _addGlow(hx, p.y + 8.85, hz, 2.6, const Color(0x55FFD27A));
                }
              case Prop.palm:
                final p = track.pose(z, sp.offset);
                if (!_visible(p.x, p.y + 6, p.z, 8)) continue;
                final s = sp.height / 2900;
                _emitMesh(Models.palm[rng % 2], p.x, p.y, p.z, yaw: (rng % 628) / 100, sx: s, sy: s, sz: s);
              case Prop.pine:
                final p = track.pose(z, sp.offset);
                if (!_visible(p.x, p.y + 5, p.z, 7)) continue;
                final s = sp.height / 2600;
                _emitMesh(Models.pine, p.x, p.y, p.z, yaw: (rng % 628) / 100, sx: s, sy: s, sz: s);
              case Prop.rock:
                final p = track.pose(z, sp.offset);
                if (!_visible(p.x, p.y + 1, p.z, 4)) continue;
                final s = sp.width * 0.0025;
                _emitMesh(Models.rock[rng % 3], p.x, p.y, p.z,
                    yaw: (rng % 628) / 100, sx: s, sy: sp.height * 0.0028, sz: s, tint: rockTint);
              case Prop.umbrella:
                final p = track.pose(z, sp.offset);
                if (!_visible(p.x, p.y + 2, p.z, 3)) continue;
                _emitMesh(Models.umbrella[rng % 2], p.x, p.y, p.z, yaw: (rng % 628) / 100);
            }
        }
      }
    }
  }

  void _buildCars() {
    final track = game.track;
    final playerZ = game.player.z;
    // models are built around the carriage; shift back so the logical position is mid-rig
    const rigOffset = 1.5 / Geo.unitScale;
    void rig(List<Mesh> frames, double z, double x, int color, int coat, double gait, double yawOffset,
        {double roll = 0, String? name, bool lamps = true, bool isYou = false}) {
      if (z < playerZ - 20 * World.segmentLength || z > playerZ + 170 * World.segmentLength) return;
      final p = track.pose(z - rigOffset, x);
      if (!_visible(p.x, p.y + 1.2, p.z, 4)) return;
      // a rival behind you sits between the camera and your carriage: hide it rather than let it
      // fill the screen (your own rig is ~8 m from the camera, one alongside you is about the same)
      if (!isYou && _depthOf(p.x, p.y, p.z) < 5.5) return;
      final yaw = p.heading + yawOffset;
      final frame = ((gait % 1) * Models.frames).floor() % Models.frames;
      _emitMesh(frames[frame], p.x, p.y, p.z, yaw: yaw, pitch: -p.pitch, roll: roll, body: color, coat: coat);
      if (_loc.night && lamps) {
        final sy = math.sin(yaw), cy = math.cos(yaw);
        // carriage lanterns and tail lamps
        _addGlow(p.x + cy * 0.78 + sy * 0.22, p.y + 1.75, p.z - sy * 0.78 + cy * 0.22, 0.8, const Color(0x55FFD27A));
        _addGlow(p.x - cy * 0.78 + sy * 0.22, p.y + 1.75, p.z + sy * 0.78 + cy * 0.22, 0.8, const Color(0x55FFD27A));
        _addGlow(p.x - sy * 1.4, p.y + 1.0, p.z - cy * 1.4, 0.7, const Color(0x44FF2030));
      }
      if (name != null) {
        final d = _depthOf(p.x, p.y, p.z);
        final s = _project(p.x + math.sin(yaw) * 1.5, p.y + 2.7, p.z + math.cos(yaw) * 1.5);
        if (s != null && d < 90) _tags.add(_Tag(s, name, Color(color), d));
      }
    }

    if (game.phase != Phase.menu) {
      for (final t in game.traffic) {
        rig(Models.cart, t.z, t.x, t.color, 0xFF8A6A4A, t.gait, 0, lamps: false);
      }
      for (final r in game.racers) {
        if (r.isPlayer) continue;
        rig(Models.carriage, r.z, r.x, r.color, r.coat, r.gait, (r.targetX - r.x).clamp(-0.4, 0.4) * 0.35,
            name: '${r.flag} ${r.name}'.trim());
      }
      final p = game.player;
      rig(Models.carriage, playerZ, p.x, Game.playerColor, p.coat, p.gait, game.visualSteer * 0.16,
          roll: game.visualSteer * 0.04, isYou: true);
    }
  }

  void _buildParticles() {
    for (final q in game.particles) {
      final d = _depthOf(q.x, q.y, q.z);
      if (d < _near || d > 160) continue;
      final at = _project(q.x, q.y, q.z);
      if (at == null) continue;
      final fade = (q.life / q.maxLife).clamp(0.0, 1.0);
      final dust = q.gravity == 0;
      if (!dust && d < 2) continue; // chunks right at the lens would fill the screen
      final alpha = dust ? 0.8 * fade : fade;
      final color = Color(_fogMix(q.color, d)).withValues(alpha: alpha);
      _specials.add(_Special.particle(d, at, q.size * _f / d, color, soft: dust));
    }
  }

  void _addGlow(double x, double y, double z, double radius, Color color) {
    final d = _depthOf(x, y, z);
    if (d < _near || d > 220) return;
    final s = _project(x, y, z);
    if (s == null) return;
    _specials.add(_Special.glow(d - 0.5, s, radius * _f / d, color.withValues(alpha: color.a * (1 - d / 240))));
  }

  /// The game's name on the sign gantry: the text is drawn through a perspective canvas transform onto the board.
  void _addBannerText(Pose p) {
    final tp = _bannerImage;
    final sh = math.sin(p.heading), ch = math.cos(p.heading);
    // board face (local z = -0.13): x from -6.6..6.6, y from 7.3..8.9
    const boardW = 13.2, boardH = 1.5;
    final scale = math.min(boardW / tp.width, boardH / tp.height);
    final ox = -tp.width * scale / 2, oy = 8.1 + tp.height * scale / 2;
    // world(u, v) = P + R * (ox + u*scale) + Up * (oy - v*scale) + F * (-0.13)
    final rx = ch, rz = -sh; // road right
    final px = p.x + rx * ox - sh * 0.13, py = p.y + oy, pz = p.z + rz * ox - ch * 0.13;
    final d = _depthOf(p.x, p.y + 8, p.z);
    if (d < 2 || d > 300) return;
    // camera-space affine coefficients of (u, v)
    double camX(double x, double y, double z) => (x - _camX) * _rx + (y - _camY) * _ry + (z - _camZ) * _rz;
    double camY(double x, double y, double z) => (x - _camX) * _ux + (y - _camY) * _uy + (z - _camZ) * _uz;
    double camZ(double x, double y, double z) => (x - _camX) * _fx + (y - _camY) * _fy + (z - _camZ) * _fz;
    final x0 = camX(px, py, pz), y0 = camY(px, py, pz), z0 = camZ(px, py, pz);
    final xu = camX(px + rx * scale, py, pz + rz * scale) - x0;
    final yu = camY(px + rx * scale, py, pz + rz * scale) - y0;
    final zu = camZ(px + rx * scale, py, pz + rz * scale) - z0;
    final xv = camX(px, py - scale, pz) - x0, yv = camY(px, py - scale, pz) - y0, zv = camZ(px, py - scale, pz) - z0;
    // every corner must be in front of the camera
    for (final (u, v) in [(0.0, 0.0), (tp.width, 0.0), (0.0, tp.height), (tp.width, tp.height)]) {
      if (z0 + zu * u + zv * v < _near + 0.5) return;
    }
    // screen = (f*xc + cx*zc, -f*yc + cy*zc, zc) as a projective map of (u, v, 1)
    final m = Float64List(16);
    void set(int row, double a, double b, double c) {
      m[0 * 4 + row] = a; // column 0: u
      m[1 * 4 + row] = b; // column 1: v
      m[3 * 4 + row] = c; // column 3: constant
    }

    set(0, _f * xu + _cx * zu, _f * xv + _cx * zv, _f * x0 + _cx * z0);
    set(1, -_f * yu + _cy * zu, -_f * yv + _cy * zv, -_f * y0 + _cy * z0);
    set(3, zu, zv, z0);
    m[10] = 1;
    _specials.add(_Special.image(d - 0.3, m, tp, 1 - ((d - _fogStart) / (_far - _fogStart)).clamp(0.0, 1.0)));
  }

  // ---------- sort + draw ----------
  void _flush(Canvas canvas) {
    final total = _n + _specials.length;
    for (var s = 0; s < _specials.length; s++) {
      _depth[_n + s] = _specials[s].depth;
    }
    final order = List<int>.generate(total, (i) => i);
    order.sort((a, b) => _depth[b].compareTo(_depth[a])); // far to near
    final pos = Float32List(_n * 6);
    final col = Int32List(_n * 3);
    var k = 0, batchStart = 0;
    final paint = Paint();
    void drawBatch() {
      if (k == batchStart) return;
      final v = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(pos, batchStart * 6, k * 6),
        colors: Int32List.sublistView(col, batchStart * 3, k * 3),
      );
      canvas.drawVertices(v, BlendMode.dst, paint);
      v.dispose();
      batchStart = k;
    }

    for (final idx in order) {
      if (idx < _n) {
        pos.setRange(k * 6, k * 6 + 6, _pos, idx * 6);
        col.setRange(k * 3, k * 3 + 3, _col, idx * 3);
        k++;
      } else {
        drawBatch();
        _specials[idx - _n].draw(canvas);
      }
    }
    drawBatch();
  }

  void _drawTags(Canvas canvas) {
    _tags.sort((a, b) => a.depth.compareTo(b.depth));
    final placed = <Rect>[];
    for (final t in _tags) {
      final tp = _nameTags.putIfAbsent(t.name, () => _label(t.name, Colors.white, size: 28, spacing: 2));
      final fade = (1 - t.depth / 90).clamp(0.0, 1.0);
      final s = (0.3 + 0.3 * fade).clamp(0.3, 0.6);
      final w = tp.width * s, h = tp.height * s;
      final area = Rect.fromCenter(center: t.at.translate(0, -h / 2), width: w + 10, height: h + 4);
      if (placed.any((r) => r.overlaps(area))) continue;
      placed.add(area);
      canvas.drawRRect(RRect.fromRectAndRadius(area, const Radius.circular(6)),
          Paint()..color = Colors.black.withValues(alpha: 0.55 * fade));
      canvas.drawRect(Rect.fromLTWH(area.left, area.bottom - 2, area.width, 2),
          Paint()..color = t.color.withValues(alpha: fade));
      canvas.save();
      canvas.translate(t.at.dx - w / 2, t.at.dy - h - 2);
      canvas.scale(s);
      canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: fade));
      tp.paint(canvas, Offset.zero);
      canvas.restore();
      canvas.restore();
    }
  }

  // ---------- sky + far scenery (2D, rotates with the camera heading) ----------
  double _azimuthX(double az) {
    var a = (az - _heading) % (math.pi * 2);
    if (a > math.pi) a -= math.pi * 2;
    return _cx + _f * math.tan(a.clamp(-1.4, 1.4));
  }

  void _drawSky(Canvas canvas, double horizon) {
    final sky = Rect.fromLTRB(-20, -20, _w + 20, horizon + 2);
    canvas.drawRect(sky, Paint()..shader = ui.Gradient.linear(sky.topCenter, sky.bottomCenter, _loc.sky, [0, 0.6, 1]));
    final shift = _heading * _f; // pixels per radian of turning

    if (_loc.night) {
      final starPaint = Paint();
      for (var i = 0; i < _stars.length; i++) {
        final s = _stars[i];
        final x = (s.dx * _f * 2 - shift) % (_w * 2.2) - _w * 0.6;
        final tw = 0.5 + 0.5 * math.sin(game.time * 2 + i);
        starPaint.color = Colors.white.withValues(alpha: 0.25 + 0.55 * tw * (1 - s.dy * 0.6));
        canvas.drawCircle(Offset(x, horizon - 20 - s.dy * (horizon + 40)), i % 9 == 0 ? 1.4 : 0.8, starPaint);
      }
    }

    // sun / moon fixed in the world, so it swings around as the road turns
    final big = _loc.sunHeight < 0.3;
    final sunX = _azimuthX(0.35);
    final sunY = horizon - (horizon + 20) * _loc.sunHeight * 0.85 - (big ? -_w * 0.05 : 0);
    final r = big ? _w * 0.16 : 22.0;
    final c = Offset(sunX, sunY);
    canvas.drawCircle(c, r * 3.5,
        Paint()..shader = ui.Gradient.radial(c, r * 3.5, [_loc.sunColor.withValues(alpha: 0.45), Colors.transparent]));
    canvas.drawCircle(c, r, Paint()..color = _loc.sunColor);
    if (_loc.night) canvas.drawCircle(c + Offset(r * 0.3, -r * 0.2), r * 0.78, Paint()..color = const Color(0x220A0820));

    final hz = horizon;
    switch (_loc.far) {
      case FarLayer.city:
        _drawSkyline(canvas, shift, hz);
      case FarLayer.dunes:
        _drawRidge(canvas, shift * 0.8, hz, _h * 0.07, 0.9, 3, _loc.farA, smooth: true);
        _drawRidge(canvas, shift, hz, _h * 0.045, 1.7, 11, _loc.farB, smooth: true);
      case FarLayer.mountains:
        _drawRidge(canvas, shift * 0.8, hz, _h * 0.17, 2.3, 5, _loc.farA, snow: true);
        _drawRidge(canvas, shift, hz, _h * 0.1, 3.7, 9, _loc.farB, snow: true);
      case FarLayer.sea:
        _drawSea(canvas, shift, hz);
    }
  }

  void _drawSkyline(Canvas canvas, double shift, double hz) {
    final r = math.Random(3);
    final body = Paint()..color = _loc.farA;
    final win = Paint()..color = _loc.windowColor.withValues(alpha: 0.8);
    const period = 2400.0;
    var x = 0.0;
    final rects = <Rect>[];
    while (x < period) {
      final w = 14 + r.nextDouble() * 40;
      final h = _h * (0.03 + r.nextDouble() * 0.11) * _loc.skylineHeight;
      rects.add(Rect.fromLTWH(x, -h, w, h + 3));
      x += w;
    }
    for (final b in rects) {
      final sx = (b.left - shift) % period;
      for (final base in [sx - period, sx]) {
        if (base > _w || base + b.width < 0) continue;
        final rect = b.shift(Offset(base - b.left, hz));
        canvas.drawRect(rect, body);
        final wr = math.Random(b.left.toInt());
        for (var wy = rect.top + 4; wy < rect.bottom - 4; wy += 6) {
          for (var wx = rect.left + 3; wx < rect.right - 3; wx += 5) {
            if (wr.nextDouble() < 0.18) canvas.drawRect(Rect.fromLTWH(wx, wy, 1.6, 2), win);
          }
        }
      }
    }
  }

  void _drawRidge(Canvas canvas, double shift, double hz, double height, double freq, int seed, Color color,
      {bool smooth = false, bool snow = false}) {
    final rnd = math.Random(seed);
    final phases = List.generate(3, (_) => rnd.nextDouble() * math.pi * 2);
    double hAt(double x) {
      final u = (x + shift) / _w;
      var v = 0.5 + 0.3 * math.sin(u * freq * 2 + phases[0]) + 0.15 * math.sin(u * freq * 5.3 + phases[1]);
      if (!smooth) v += 0.12 * (math.sin(u * freq * 13 + phases[2])).abs();
      return height * v.clamp(0.05, 1.2);
    }

    final path = Path()..moveTo(-20, hz + 3);
    const step = 6.0;
    for (var x = -20.0; x <= _w + 20; x += step) {
      path.lineTo(x, hz - hAt(x));
    }
    path
      ..lineTo(_w + 20, hz + 3)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    if (snow) {
      final cap = Path();
      for (var x = -20.0; x <= _w + 20; x += step) {
        final h = hAt(x);
        if (h > height * 0.62) {
          cap
            ..moveTo(x, hz - h)
            ..lineTo(x + step, hz - hAt(x + step))
            ..lineTo(x + step, hz - h * 0.86)
            ..lineTo(x, hz - h * 0.86)
            ..close();
        }
      }
      canvas.drawPath(cap, Paint()..color = Colors.white.withValues(alpha: 0.9));
    }
  }

  void _drawSea(Canvas canvas, double shift, double hz) {
    final band = Rect.fromLTRB(-20, hz - _h * 0.02, _w + 20, hz + 3);
    canvas.drawRect(band, Paint()..shader = ui.Gradient.linear(band.topCenter, band.bottomCenter, [_loc.farA, _loc.farB]));
    final glint = Paint();
    final r = math.Random(5);
    for (var i = 0; i < 40; i++) {
      final x = (r.nextDouble() * _w * 1.3 - shift * 2) % (_w * 1.3);
      final y = band.top + r.nextDouble() * band.height;
      glint.color = Colors.white.withValues(alpha: 0.6 * (0.5 + 0.5 * math.sin(game.time * 3 + i)));
      canvas.drawRect(Rect.fromLTWH(x, y, 6 + r.nextDouble() * 10, 1.2), glint);
    }
    _drawRidge(canvas, shift * 0.6, hz - _h * 0.02, _h * 0.025, 0.7, 21, const Color(0xFF6E8FA8), smooth: true);
  }

  @override
  bool shouldRepaint(covariant RacePainter oldDelegate) => false;
}

class _Special {
  _Special.glow(this.depth, Offset at, double radius, Color color)
      : _at = at,
        _radius = radius,
        _color = color,
        _matrix = null,
        _image = null,
        _alpha = 1;
  _Special.particle(this.depth, Offset at, double radius, Color color, {required bool soft})
      : _at = at,
        _radius = radius,
        _color = color,
        _matrix = null,
        _image = null,
        _alpha = soft ? -1 : -2;
  _Special.image(this.depth, Float64List matrix, ui.Image image, double alpha)
      : _matrix = matrix,
        _image = image,
        _alpha = alpha,
        _at = Offset.zero,
        _radius = 0,
        _color = Colors.transparent;

  final double depth;
  final Offset _at;
  final double _radius;
  final Color _color;
  final Float64List? _matrix;
  final ui.Image? _image;
  final double _alpha;

  void draw(Canvas canvas) {
    if (_matrix != null) {
      canvas.save();
      canvas.transform(_matrix);
      canvas.drawImage(
          _image!,
          Offset.zero,
          Paint()
            ..color = Colors.white.withValues(alpha: _alpha)
            ..filterQuality = FilterQuality.medium);
      canvas.restore();
      return;
    }
    if (_alpha == -1) {
      // soft dust puff
      if (_radius < 0.5) return;
      canvas.drawCircle(
          _at,
          _radius,
          Paint()
            ..shader = ui.Gradient.radial(_at, _radius, [_color, _color.withValues(alpha: 0)]));
      return;
    }
    if (_alpha == -2) {
      // hard chunk of debris
      final r = _radius.clamp(1.2, 9.0);
      canvas.drawRect(Rect.fromCenter(center: _at, width: r * 2, height: r * 1.6), Paint()..color = _color);
      return;
    }
    if (_radius < 1) return;
    canvas.drawCircle(
      _at,
      _radius,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(_at, _radius, [_color, _color.withValues(alpha: 0)]),
    );
  }
}

class _Tag {
  _Tag(this.at, this.name, this.color, this.depth);
  final Offset at;
  final String name;
  final Color color;
  final double depth;
}
