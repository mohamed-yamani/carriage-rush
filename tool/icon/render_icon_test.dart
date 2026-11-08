// Renders the app icon and Play Store artwork from the game's own 3D models, then writes them to
// assets/icon/. Run from the project root:
//   flutter test tool/icon/render_icon_test.dart
//   dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_racer/game/meshes.dart';

const _sky = [Color(0xFF1B1446), Color(0xFF6A2A7A), Color(0xFFE85A6A), Color(0xFFFFB25E)];
const _body = 0xFFFF2D55; // the player's carriage
const _coat = 0xFFF2EEE6; // white horse

/// A tiny camera + painter's-algorithm renderer for icon shots (same idea as the game's renderer).
class _Shot {
  _Shot(this.size, {required List<double> eye, required List<double> target, required double fovDeg, Offset? center})
      : _eye = eye,
        _c = center ?? Offset(size.width / 2, size.height / 2) {
    var fx = target[0] - eye[0], fy = target[1] - eye[1], fz = target[2] - eye[2];
    final l = math.sqrt(fx * fx + fy * fy + fz * fz);
    fx /= l;
    fy /= l;
    fz /= l;
    var rx = fz, rz = -fx;
    final rl = math.sqrt(rx * rx + rz * rz);
    rx /= rl;
    rz /= rl;
    _r = [rx, 0, rz];
    _u = [fy * rz, fz * rx - fx * rz, -fy * rx];
    _f = [fx, fy, fz];
    _focal = (size.height / 2) / math.tan(fovDeg / 2 * math.pi / 180);
  }

  final Size size;
  final List<double> _eye;
  final Offset _c;
  late final List<double> _r, _u, _f;
  late final double _focal;
  final _tris = <(double, List<Offset>, int)>[];

  static const _light = [-0.45, 0.8, 0.55];

  List<double> _cam(List<double> p) {
    final dx = p[0] - _eye[0], dy = p[1] - _eye[1], dz = p[2] - _eye[2];
    return [dx * _r[0] + dz * _r[2], dx * _u[0] + dy * _u[1] + dz * _u[2], dx * _f[0] + dy * _f[1] + dz * _f[2]];
  }

  Offset _project(List<double> p) => _c + Offset(_focal * p[0] / p[2], -_focal * p[1] / p[2]);

  void tri(List<double> a, List<double> b, List<double> c, int color, {double bias = 0}) {
    final pa = _cam(a), pb = _cam(b), pc = _cam(c);
    if (pa[2] < 0.3 || pb[2] < 0.3 || pc[2] < 0.3) return;
    _tris.add(((pa[2] + pb[2] + pc[2]) / 3 + bias, [_project(pa), _project(pb), _project(pc)], color));
  }

  void quad(List<double> a, List<double> b, List<double> c, List<double> d, int color, {double bias = 0}) {
    tri(a, b, c, color, bias: bias);
    tri(a, c, d, color, bias: bias);
  }

  void mesh(Mesh m, {int body = _body, int coat = _coat}) {
    final l = math.sqrt(_light.fold(0.0, (s, v) => s + v * v));
    for (var t = 0; t < m.count; t++) {
      final v = m.v.sublist(t * 9, t * 9 + 9);
      final a = [v[0], v[1], v[2]], b = [v[3], v[4], v[5]], c = [v[6], v[7], v[8]];
      final nx = m.n[t * 3], ny = m.n[t * 3 + 1], nz = m.n[t * 3 + 2];
      final mx = (a[0] + b[0] + c[0]) / 3 - _eye[0];
      final my = (a[1] + b[1] + c[1]) / 3 - _eye[1];
      final mz = (a[2] + b[2] + c[2]) / 3 - _eye[2];
      final facing = nx * mx + ny * my + nz * mz;
      if ((m.f[t] & kTwoSided) == 0 && facing > 0) continue;
      var col = switch (m.c[t]) {
        kBody => body,
        kBodyDark => shade(body, 0.5),
        kCoat => coat,
        kCoatDark => shade(coat, 0.45),
        final x => x,
      };
      if ((m.f[t] & kEmissive) == 0) {
        var d = (nx * _light[0] + ny * _light[1] + nz * _light[2]) / l;
        if ((m.f[t] & kTwoSided) != 0 && facing > 0) d = -d;
        col = shade(col, 0.55 + 0.6 * math.max(0, d));
      }
      tri(a, b, c, col, bias: (m.f[t] & kDecal) != 0 ? -0.05 : 0);
    }
  }

  void draw(Canvas canvas) {
    _tris.sort((x, y) => y.$1.compareTo(x.$1));
    final pos = <Offset>[], cols = <Color>[];
    for (final (_, pts, c) in _tris) {
      pos.addAll(pts);
      cols.addAll([Color(c), Color(c), Color(c)]);
    }
    canvas.drawVertices(ui.Vertices(VertexMode.triangles, pos, colors: cols), BlendMode.dst, Paint());
  }
}

void _skyAndGround(Canvas c, Size s, {required Offset sun, required double horizon}) {
  final r = Offset.zero & s;
  c.drawRect(r, Paint()..shader = ui.Gradient.linear(r.topCenter, Offset(0, horizon), _sky, [0, 0.35, 0.75, 1]));
  final sr = s.shortestSide * 0.2;
  c.drawCircle(sun, sr * 3,
      Paint()..shader = ui.Gradient.radial(sun, sr * 3, [const Color(0x88FFD9A0), const Color(0x00FFD9A0)]));
  c.drawCircle(sun, sr, Paint()..color = const Color(0xFFFFE6A8));
  // distant hills on the horizon
  final hills = Path()..moveTo(0, horizon + 2);
  for (var i = 0; i <= 40; i++) {
    final x = s.width * i / 40;
    hills.lineTo(x, horizon - s.height * (0.03 + 0.025 * math.sin(i * 0.7) + 0.015 * math.sin(i * 1.9 + 1)));
  }
  hills
    ..lineTo(s.width, horizon + 2)
    ..close();
  c.drawPath(hills, Paint()..color = const Color(0xFF9A4A6A));
  c.drawRect(Rect.fromLTRB(0, horizon, s.width, s.height), Paint()..color = const Color(0xFFD99A62));
}

/// Cobbled road running away from the camera behind the carriage, with stone curbs and sand verges.
void _road(_Shot shot) {
  int stone(int i, int j) {
    final h = ((i * 73856093) ^ (j * 19349663)) & 0xFF;
    return shade(0xFF8A7E78, 0.8 + 0.35 * h / 255);
  }

  for (var i = -2; i < 60; i++) {
    final z0 = 6.0 - i * 2.0, z1 = z0 - 2.0;
    final shift = i.isOdd ? 0.75 : 0.0;
    final edges = <double>[-6.0];
    for (var x = -6.0 + 1.5 - shift; x < 5.99; x += 1.5) {
      if (x > -5.99) edges.add(x);
    }
    edges.add(6.0);
    for (var k = 0; k + 1 < edges.length; k++) {
      shot.quad([edges[k], 0, z0], [edges[k + 1], 0, z0], [edges[k + 1], 0, z1], [edges[k], 0, z1], stone(i, k),
          bias: 3);
    }
    final curb = i.isEven ? 0xFFEDE3D0 : 0xFFB89A70;
    for (final (a, b) in [(-6.8, -6.0), (6.0, 6.8)]) {
      shot.quad([a, 0.18, z0], [b, 0.18, z0], [b, 0.18, z1], [a, 0.18, z1], curb, bias: 2.9);
    }
    final sand = i.isEven ? 0xFFE3B47A : 0xFFDDAA6E;
    shot.quad([-60, 0, z0], [-6.8, 0, z0], [-6.8, 0, z1], [-60, 0, z1], sand, bias: 3.1);
    shot.quad([6.8, 0, z0], [60, 0, z0], [60, 0, z1], [6.8, 0, z1], sand, bias: 3.1);
  }
}

/// Renders the scene. [withRig]/[withScene] split it into the Android adaptive layers.
void paintScene(Canvas canvas, Size size,
    {required double fov, Offset? center, bool withRig = true, bool withScene = true, double eyeX = 3.2}) {
  final eye = [eyeX, 2.1, 10.0];
  const target = [0.1, 1.3, 1.3];
  final shot = _Shot(size, eye: eye, target: target, fovDeg: fov, center: center);
  // horizon: a point far down the road at eye height
  final far = shot._cam([eye[0], eye[1], -5000]);
  final horizon = shot._project(far).dy;
  if (withScene) {
    _skyAndGround(canvas, size, sun: Offset(size.width * 0.28, horizon - size.height * 0.1), horizon: horizon);
    _road(shot);
    shot.draw(canvas);
  }
  if (withRig) {
    final rig = _Shot(size, eye: eye, target: target, fovDeg: fov, center: center);
    rig.mesh(Models.carriage[3]);
    rig.draw(canvas);
  }
}

Future<void> _save(ui.Image img, String path) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

Future<ui.Image> _render(int w, int h, void Function(Canvas) draw) {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec));
  return rec.endRecording().toImage(w, h);
}

void main() {
  testWidgets('render icon artwork', (tester) async {
    await tester.runAsync(() async {
      final font = FontLoader('Title')
        ..addFont(Future.value(
            ByteData.sublistView(File('/System/Library/Fonts/Supplemental/Arial Black.ttf').readAsBytesSync())));
      await font.load();
      const sq = Size(1024, 1024);

      // full-bleed icon (iOS, legacy Android, Play 512): tight framing
      await _save(await _render(1024, 1024, (c) => paintScene(c, sq, fov: 24, center: const Offset(430, 560))),
          'assets/icon/icon.png');
      await _save(await _render(512, 512, (c) {
        c.scale(0.5);
        paintScene(c, sq, fov: 24, center: const Offset(430, 560));
      }), 'assets/icon/play_store_512.png');
      // adaptive layers share one looser camera so the rig sits inside the 66% safe zone
      await _save(await _render(1024, 1024, (c) => paintScene(c, sq, fov: 36, center: const Offset(450, 540), withRig: false)),
          'assets/icon/icon_background.png');
      await _save(await _render(1024, 1024, (c) => paintScene(c, sq, fov: 36, center: const Offset(450, 540), withScene: false)),
          'assets/icon/icon_foreground.png');

      // Play feature graphic 1024 x 500: carriage on the left, title on the right
      await _save(await _render(1024, 500, (c) {
        paintScene(c, const Size(1024, 500), fov: 26, center: const Offset(290, 270), eyeX: 2.6);
        final title = TextPainter(
          text: const TextSpan(children: [
            TextSpan(
                text: 'CARRIAGE\nRUSH\n',
                style: TextStyle(fontFamily: 'Title', fontSize: 62, color: Color(0xFFFFE08A), height: 1.0, shadows: [
                  Shadow(color: Color(0xCC1B1446), blurRadius: 16, offset: Offset(0, 4)),
                ])),
            TextSpan(
                text: 'HORSE RACE',
                style: TextStyle(
                    fontFamily: 'Title',
                    fontSize: 28,
                    color: Colors.white,
                    height: 1.3,
                    letterSpacing: 6,
                    shadows: [Shadow(color: Color(0xCC1B1446), blurRadius: 12)])),
          ]),
          textDirection: TextDirection.ltr,
        )..layout();
        title.paint(c, const Offset(600, 110));
      }), 'assets/icon/feature_graphic.png');
    });
  });
}
