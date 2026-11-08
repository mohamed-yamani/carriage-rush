// Draws the app icon and Play Store artwork with Canvas and writes them to assets/icon/.
// Run from the project root:   flutter test tool/icon/render_icon_test.dart
// then:                        dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _sky = [Color(0xFF2B1A4A), Color(0xFF7A2E6B), Color(0xFFE0566B), Color(0xFFFFB259)];
const _gold = Color(0xFFFFC94A);
const _goldDark = Color(0xFFB8801E);
const _coat = Color(0xFFF6EEDF);
const _coatShade = Color(0xFFD9C9AE);
const _mane = Color(0xFF3A2414);

/// Sunset background with a soft glow where the "sun" wheel sits.
void paintBackground(Canvas c, Size s, {Offset? sun}) {
  final r = Offset.zero & s;
  c.drawRect(r, Paint()..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, _sky, [0, 0.35, 0.7, 1]));
  final glow = sun ?? Offset(s.width * 0.42, s.height * 0.42);
  c.drawCircle(
      glow,
      s.shortestSide * 0.6,
      Paint()
        ..shader = ui.Gradient.radial(
            glow, s.shortestSide * 0.6, [const Color(0x66FFD9A0), const Color(0x00FFD9A0)]));
  // dunes along the bottom, like the Sahara course
  final h = s.height;
  final dune = Path()..moveTo(0, h);
  for (var i = 0; i <= 40; i++) {
    final x = s.width * i / 40;
    dune.lineTo(x, h * 0.86 - math.sin(x / s.width * math.pi * 2.2 + 0.6) * h * 0.035);
  }
  dune
    ..lineTo(s.width, h)
    ..close();
  c.drawPath(dune, Paint()..color = const Color(0xFFC77A4A));
  final dune2 = Path()..moveTo(0, h);
  for (var i = 0; i <= 40; i++) {
    final x = s.width * i / 40;
    dune2.lineTo(x, h * 0.93 - math.sin(x / s.width * math.pi * 3.1 + 2) * h * 0.025);
  }
  dune2
    ..lineTo(s.width, h)
    ..close();
  c.drawPath(dune2, Paint()..color = const Color(0xFFD9925A));
}

/// Golden carriage wheel: rim, spokes, hub.
void paintWheel(Canvas c, Offset center, double r) {
  final rim = Paint()
    ..color = _gold
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.13;
  c.drawCircle(center, r, Paint()..color = const Color(0x22FFE7B0));
  c.drawCircle(center, r, rim);
  c.drawCircle(center, r * 0.82,
      Paint()
        ..color = _goldDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.03);
  final spoke = Paint()
    ..color = _gold
    ..strokeWidth = r * 0.06
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 12; i++) {
    final a = i / 12 * math.pi * 2 + 0.13;
    c.drawLine(center + Offset(math.cos(a), math.sin(a)) * r * 0.16,
        center + Offset(math.cos(a), math.sin(a)) * r * 0.88, spoke);
  }
  c.drawCircle(center, r * 0.17, Paint()..color = _gold);
  c.drawCircle(center, r * 0.08, Paint()..color = _goldDark);
}

/// Horse head in profile, facing right, inside a 1000 x 1000 design box.
void paintHorse(Canvas c) {
  // neck + head silhouette
  final head = Path()
    ..moveTo(250, 1000)
    ..cubicTo(255, 760, 330, 470, 470, 300) // back of the neck up to the poll
    ..lineTo(505, 150) // ear
    ..lineTo(575, 268)
    ..cubicTo(650, 300, 745, 420, 805, 560) // forehead down the face
    ..cubicTo(845, 650, 870, 720, 835, 765) // muzzle
    ..cubicTo(805, 805, 735, 800, 700, 770) // lips and chin
    ..cubicTo(650, 730, 580, 700, 530, 640) // jaw
    ..cubicTo(560, 760, 625, 880, 650, 1000) // throat down the front of the neck
    ..close();
  // far ear, a shade darker, peeking out behind the near one
  final farEar = Path()
    ..moveTo(430, 300)
    ..lineTo(440, 165)
    ..lineTo(500, 285)
    ..close();
  c.drawPath(farEar, Paint()..color = _coatShade);
  c.drawPath(
      Path()
        ..moveTo(445, 280)
        ..lineTo(447, 205)
        ..lineTo(480, 275)
        ..close(),
      Paint()..color = const Color(0xFFB89A7A));

  // a soft drop shadow so the head lifts off the wheel
  c.drawPath(head.shift(const Offset(14, 18)), Paint()..color = const Color(0x55000000));
  c.drawPath(
      head,
      Paint()
        ..shader = ui.Gradient.linear(const Offset(300, 300), const Offset(800, 900), [_coat, _coatShade]));

  // cheek muscle shading
  final cheek = Path()
    ..moveTo(540, 470)
    ..cubicTo(620, 450, 690, 560, 640, 660)
    ..cubicTo(600, 700, 545, 640, 530, 600)
    ..close();
  c.drawPath(cheek, Paint()..color = const Color(0x22806040));

  // flowing mane down the back of the neck, with a forelock between the ears
  final mane = Path()
    ..moveTo(470, 300)
    ..cubicTo(400, 380, 330, 520, 300, 700)
    ..lineTo(240, 660)
    ..lineTo(275, 610)
    ..lineTo(205, 560)
    ..lineTo(270, 520)
    ..lineTo(215, 440)
    ..lineTo(300, 430)
    ..lineTo(275, 340)
    ..lineTo(360, 350)
    ..lineTo(370, 260)
    ..lineTo(430, 290)
    ..lineTo(455, 200)
    ..close();
  c.drawPath(mane, Paint()..color = _mane);
  // inner ear
  c.drawPath(
      Path()
        ..moveTo(515, 255)
        ..lineTo(512, 190)
        ..lineTo(555, 262)
        ..close(),
      Paint()..color = const Color(0xFFD9B79A));
  final forelock = Path()
    ..moveTo(520, 270)
    ..quadraticBezierTo(585, 290, 590, 345)
    ..quadraticBezierTo(560, 318, 530, 318)
    ..close();
  c.drawPath(forelock, Paint()..color = _mane);

  // bridle in gold
  final strap = Paint()
    ..color = _gold
    ..style = PaintingStyle.stroke
    ..strokeWidth = 16
    ..strokeCap = StrokeCap.round;
  c.drawLine(const Offset(560, 300), const Offset(560, 640), strap); // cheek piece
  c.drawLine(const Offset(560, 640), const Offset(780, 655), strap); // noseband
  c.drawLine(const Offset(562, 345), const Offset(650, 352), strap); // brow band
  c.drawCircle(const Offset(560, 640), 16, Paint()..color = _goldDark);

  // eye and nostril
  c.drawOval(Rect.fromCenter(center: const Offset(645, 430), width: 52, height: 40), Paint()..color = _mane);
  c.drawCircle(const Offset(655, 423), 8, Paint()..color = Colors.white);
  c.drawOval(Rect.fromCenter(center: const Offset(812, 700), width: 30, height: 20), Paint()..color = const Color(0xFF6A4A35));
}

/// The full square icon.
void paintIcon(Canvas c, double size, {bool background = true, double contentScale = 1.0}) {
  final s = Size(size, size);
  if (background) paintBackground(c, s);
  c.save();
  // centre the 1000-unit design and scale it to the icon
  final k = size / 1000 * contentScale;
  c.translate(size / 2 - 500 * k, size / 2 - 500 * k);
  c.scale(k);
  paintWheel(c, const Offset(430, 470), 330);
  paintHorse(c);
  c.restore();
}

Future<void> _save(ui.Image img, String path) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(Uint8List.view(data!.buffer));
}

Future<ui.Image> _render(int w, int h, void Function(Canvas) draw) {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec));
  return rec.endRecording().toImage(w, h);
}

void main() {
  testWidgets('render icon artwork', (tester) async {
    await tester.runAsync(() async {
      // a real font for the feature graphic (tests otherwise use a placeholder font)
      final font = FontLoader('Title')
        ..addFont(Future.value(ByteData.sublistView(File('/System/Library/Fonts/Supplemental/Arial Black.ttf').readAsBytesSync())));
      await font.load();

      // 1024 full icon (iOS, legacy Android, store)
      await _save(await _render(1024, 1024, (c) => paintIcon(c, 1024)), 'assets/icon/icon.png');
      // Android adaptive icon: foreground art inside the 66% safe zone, background separately
      await _save(await _render(1024, 1024, (c) => paintIcon(c, 1024, background: false, contentScale: 0.66)),
          'assets/icon/icon_foreground.png');
      await _save(await _render(1024, 1024, (c) => paintBackground(c, const Size(1024, 1024))),
          'assets/icon/icon_background.png');
      // Play Store 512 icon
      await _save(await _render(512, 512, (c) => paintIcon(c, 512)), 'assets/icon/play_store_512.png');

      // Play feature graphic 1024 x 500
      await _save(await _render(1024, 500, (c) {
        paintBackground(c, const Size(1024, 500), sun: const Offset(250, 250));
        c.save();
        c.translate(40, 0);
        c.scale(0.5);
        paintWheel(c, const Offset(430, 470), 330);
        paintHorse(c);
        c.restore();
        final title = TextPainter(
          text: const TextSpan(children: [
            TextSpan(
                text: 'CARRIAGE\nRUSH\n',
                style: TextStyle(fontFamily: 'Title', fontSize: 80, color: Color(0xFFFFE08A), height: 1.0, shadows: [
                  Shadow(color: Color(0xAA7A2E6B), blurRadius: 18, offset: Offset(0, 4)),
                ])),
            TextSpan(
                text: 'HORSE RACE',
                style: TextStyle(fontFamily: 'Title', fontSize: 36, color: Colors.white, height: 1.3, letterSpacing: 6)),
          ]),
          textDirection: TextDirection.ltr,
        )..layout();
        title.paint(c, const Offset(510, 70));
      }), 'assets/icon/feature_graphic.png');
    });
  });
}
