import 'dart:math' as math;

/// Colour sentinels replaced per instance (carriage paint, horse coat).
const int kBody = -1;
const int kBodyDark = -2;
const int kCoat = -3;
const int kCoatDark = -4;

/// Triangle flags.
const int kEmissive = 1; // ignores lighting (lights, lit windows)
const int kTwoSided = 2; // never back-face culled (leaves, signs)
const int kDecal = 4; // sits flat on another face: always drawn just after it (windows, trim)

/// A low-poly mesh: flat-shaded triangles with one colour each, in local space
/// (x right, y up, z forward). Normals always point away from the part's centre.
class Mesh {
  final List<double> v = []; // 9 per triangle
  final List<double> n = []; // 3 per triangle
  final List<int> c = []; // colour per triangle
  final List<int> f = []; // flags per triangle
  int get count => c.length;

  void tri(List<double> a, List<double> b, List<double> c3, int color,
      {required List<double> center, int flags = 0}) {
    final ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2];
    final wx = c3[0] - a[0], wy = c3[1] - a[1], wz = c3[2] - a[2];
    var nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len < 1e-9) return;
    nx /= len;
    ny /= len;
    nz /= len;
    final mx = (a[0] + b[0] + c3[0]) / 3 - center[0];
    final my = (a[1] + b[1] + c3[1]) / 3 - center[1];
    final mz = (a[2] + b[2] + c3[2]) / 3 - center[2];
    var p = b, q = c3;
    if (nx * mx + ny * my + nz * mz < 0) {
      nx = -nx;
      ny = -ny;
      nz = -nz;
      p = c3;
      q = b;
    }
    v.addAll([...a, ...p, ...q]);
    n.addAll([nx, ny, nz]);
    c.add(color);
    f.add(flags);
  }

  void quad(List<double> a, List<double> b, List<double> c3, List<double> d, int color,
      {required List<double> center, int flags = 0}) {
    tri(a, b, c3, color, center: center, flags: flags);
    tri(a, c3, d, color, center: center, flags: flags);
  }

  /// Axis-aligned box centred at (x, y, z) with half sizes.
  void box(double x, double y, double z, double hx, double hy, double hz, int color, {int? top, int flags = 0}) {
    final ctr = [x, y, z];
    List<double> p(int sx, int sy, int sz) => [x + sx * hx, y + sy * hy, z + sz * hz];
    quad(p(-1, 1, -1), p(1, 1, -1), p(1, 1, 1), p(-1, 1, 1), top ?? color, center: ctr, flags: flags); // top
    quad(p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1), color, center: ctr, flags: flags); // bottom
    quad(p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1), color, center: ctr, flags: flags); // front
    quad(p(-1, -1, -1), p(1, -1, -1), p(1, 1, -1), p(-1, 1, -1), color, center: ctr, flags: flags); // back
    quad(p(-1, -1, -1), p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1), color, center: ctr, flags: flags); // left
    quad(p(1, -1, -1), p(1, -1, 1), p(1, 1, 1), p(1, 1, -1), color, center: ctr, flags: flags); // right
  }

  /// Convex (z, y) profile extruded along x from -hw to +hw. [edge] colours each perimeter face.
  void prismX(List<(double, double)> profile, double hw, int side, List<int> edge) {
    var cz = 0.0, cyy = 0.0;
    for (final (z, y) in profile) {
      cz += z;
      cyy += y;
    }
    cz /= profile.length;
    cyy /= profile.length;
    final ctr = [0.0, cyy, cz];
    for (final sx in [-hw, hw]) {
      for (var i = 0; i < profile.length; i++) {
        final (z1, y1) = profile[i];
        final (z2, y2) = profile[(i + 1) % profile.length];
        tri([sx, cyy, cz], [sx, y1, z1], [sx, y2, z2], side, center: ctr);
      }
    }
    for (var i = 0; i < profile.length; i++) {
      final (z1, y1) = profile[i];
      final (z2, y2) = profile[(i + 1) % profile.length];
      quad([-hw, y1, z1], [hw, y1, z1], [hw, y2, z2], [-hw, y2, z2], edge[i], center: ctr);
    }
  }

  /// Cylinder along x (a wheel).
  void cylX(double x, double y, double z, double r, double hw, int sides, int color, int hub) {
    final ctr = [x, y, z];
    for (var i = 0; i < sides; i++) {
      final a1 = i / sides * math.pi * 2, a2 = (i + 1) / sides * math.pi * 2;
      final y1 = y + math.cos(a1) * r, z1 = z + math.sin(a1) * r;
      final y2 = y + math.cos(a2) * r, z2 = z + math.sin(a2) * r;
      quad([x - hw, y1, z1], [x + hw, y1, z1], [x + hw, y2, z2], [x - hw, y2, z2], color, center: ctr);
      tri([x - hw, y, z], [x - hw, y1, z1], [x - hw, y2, z2], hub, center: ctr);
      tri([x + hw, y, z], [x + hw, y1, z1], [x + hw, y2, z2], hub, center: ctr);
    }
  }


  /// Box rotated by [angle] around the x axis (a pitch in the y/z plane) about its own centre.
  void boxX(double x, double y, double z, double hx, double hy, double hz, double angle, int color, {int flags = 0}) {
    final ca = math.cos(angle), sa = math.sin(angle);
    List<double> p(int sx, int sy, int sz) {
      final ly = sy * hy, lz = sz * hz;
      return [x + sx * hx, y + ly * ca - lz * sa, z + ly * sa + lz * ca];
    }

    final ctr = [x, y, z];
    quad(p(-1, 1, -1), p(1, 1, -1), p(1, 1, 1), p(-1, 1, 1), color, center: ctr, flags: flags);
    quad(p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1), color, center: ctr, flags: flags);
    quad(p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1), color, center: ctr, flags: flags);
    quad(p(-1, -1, -1), p(1, -1, -1), p(1, 1, -1), p(-1, 1, -1), color, center: ctr, flags: flags);
    quad(p(-1, -1, -1), p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1), color, center: ctr, flags: flags);
    quad(p(1, -1, -1), p(1, -1, 1), p(1, 1, 1), p(1, 1, -1), color, center: ctr, flags: flags);
  }

  /// A limb hanging from [pivot] (y, z) swung by [angle]; returns the (y, z) of its lower end.
  (double, double) limb(double x, double py, double pz, double len, double half, double angle, int color) {
    final ey = py - math.cos(angle) * len, ez = pz + math.sin(angle) * len;
    boxX(x, (py + ey) / 2, (pz + ez) / 2, half, len / 2, half, -angle, color);
    return (ey, ez);
  }

  /// Spoked wheel in the y/z plane (a flat rim ring plus spokes), turned by [spin].
  void spokedWheel(double x, double y, double z, double r, double spin, int rim, int spoke) {
    const segs = 10;
    final ctr = [x - 1, y, z]; // any point off the plane; the ring is two-sided anyway
    for (var i = 0; i < segs; i++) {
      final a1 = i / segs * math.pi * 2, a2 = (i + 1) / segs * math.pi * 2;
      final ri = r * 0.82;
      quad([x, y + math.cos(a1) * ri, z + math.sin(a1) * ri], [x, y + math.cos(a1) * r, z + math.sin(a1) * r],
          [x, y + math.cos(a2) * r, z + math.sin(a2) * r], [x, y + math.cos(a2) * ri, z + math.sin(a2) * ri], rim,
          center: ctr, flags: kTwoSided);
    }
    for (var k = 0; k < 3; k++) {
      boxX(x, y, z, 0.025, r * 0.82, 0.025, spin + k * math.pi / 3, spoke);
    }
    box(x, y, z, 0.06, 0.07, 0.07, spoke);
  }

  /// Cone standing on y0 (pine tiers, umbrellas).
  void cone(double x, double y0, double z, double r, double h, int sides, int color, {int? bottom}) {
    final ctr = [x, y0 + h * 0.25, z];
    final tip = [x, y0 + h, z];
    for (var i = 0; i < sides; i++) {
      final a1 = i / sides * math.pi * 2, a2 = (i + 1) / sides * math.pi * 2;
      final p1 = [x + math.cos(a1) * r, y0, z + math.sin(a1) * r];
      final p2 = [x + math.cos(a2) * r, y0, z + math.sin(a2) * r];
      tri(p1, p2, tip, color, center: ctr);
      if (bottom != null) tri([x, y0, z], p1, p2, bottom, center: [x, y0 + h, z]);
    }
  }
}

int _shade(int argb, double k) {
  final r = ((argb >> 16) & 0xFF) * k, g = ((argb >> 8) & 0xFF) * k, b = (argb & 0xFF) * k;
  return 0xFF000000 | (r.round().clamp(0, 255) << 16) | (g.round().clamp(0, 255) << 8) | b.round().clamp(0, 255);
}

// ---------- the models ----------
class Models {
  // ---------- horses and carriages (8 animation frames each) ----------
  static const frames = 8;

  /// A galloping horse whose body sits around z = [z0]. [t] is the gallop phase 0..1.
  static void _horse(Mesh m, double z0, double t) {
    const tau = math.pi * 2;
    final bob = math.sin(t * tau * 2) * 0.06;
    final by = 1.28 + bob;
    // body, chest and rump
    m.boxX(0, by, z0, 0.3, 0.3, 0.8, 0, kCoat);
    m.boxX(0, by + 0.04, z0 + 0.72, 0.29, 0.33, 0.22, 0.2, kCoat);
    m.boxX(0, by + 0.06, z0 - 0.7, 0.31, 0.31, 0.2, -0.15, kCoat);
    // neck, mane, head, ears
    final nod = math.sin(t * tau * 2 + 1) * 0.08;
    m.boxX(0, by + 0.45, z0 + 1.0, 0.15, 0.45, 0.2, 0.62 + nod, kCoat);
    m.boxX(0, by + 0.55, z0 + 0.86, 0.05, 0.42, 0.08, 0.62 + nod, kCoatDark);
    m.boxX(0, by + 0.78, z0 + 1.42, 0.13, 0.13, 0.33, 0.55 + nod, kCoat);
    m.boxX(0, by + 0.66, z0 + 1.7, 0.11, 0.1, 0.12, 0.55 + nod, kCoatDark);
    for (final ex in [-0.07, 0.07]) {
      m.box(ex, by + 1.02, z0 + 1.28, 0.03, 0.08, 0.03, kCoatDark);
    }
    // tail streams out behind
    m.boxX(0, by - 0.05, z0 - 1.05, 0.07, 0.38, 0.07, -0.9 + math.sin(t * tau) * 0.15, kCoatDark);
    // legs: rotary gallop, each leg a quarter cycle apart
    final legs = [(-0.2, 0.62, 0.0), (0.2, 0.62, 0.12), (-0.2, -0.62, 0.5), (0.2, -0.62, 0.62)];
    for (final (lx, lz, off) in legs) {
      final a = math.sin((t + off) * tau) * 0.55;
      final (ky, kz) = m.limb(lx, by - 0.2, z0 + lz, 0.55, 0.075, a, kCoat);
      final shin = a + (math.sin((t + off) * tau + 1.2) > 0 ? 0.7 : 0.0) * (lz > 0 ? -1 : 1);
      final (fy, fz) = m.limb(lx, ky, kz, 0.5, 0.06, shin, kCoat);
      m.box(lx, fy + 0.04, fz, 0.07, 0.05, 0.08, 0xFF2A2420);
    }
  }

  static void _driver(Mesh m, double z, double seatY) {
    m.box(0, seatY + 0.32, z, 0.22, 0.3, 0.16, 0xFF2B2F45); // coat
    m.box(0, seatY + 0.74, z + 0.02, 0.11, 0.12, 0.11, 0xFFE0B48C); // face
    m.box(0, seatY + 0.9, z + 0.02, 0.16, 0.02, 0.16, 0xFF1A1A1A); // hat brim
    m.box(0, seatY + 1.0, z + 0.02, 0.1, 0.09, 0.1, 0xFF1A1A1A); // hat
    m.box(0, seatY + 0.42, z + 0.3, 0.18, 0.05, 0.16, 0xFF2B2F45); // arms with reins
  }

  /// Racing carriage: painted cabin with windows and gold trim, coachman, horse in the shafts.
  static final List<Mesh> carriage = List.generate(frames, (f) {
    final m = Mesh();
    final t = f / frames;
    const gold = 0xFFD9A93A, wood = 0xFF4A2E1A;
    final spin = t * math.pi / 3; // one spoke spacing per gallop cycle
    for (final wx in [-0.88, 0.88]) {
      m.spokedWheel(wx, 0.62, -1.0, 0.62, spin, 0xFF3A2414, gold);
      m.spokedWheel(wx, 0.46, 0.75, 0.46, spin * 1.35, 0xFF3A2414, gold);
    }
    m.box(0, 0.62, -1.0, 0.86, 0.03, 0.03, wood); // axles
    m.box(0, 0.46, 0.75, 0.86, 0.03, 0.03, wood);
    m.box(0, 0.86, -0.25, 0.62, 0.08, 1.15, wood); // chassis
    // cabin
    m.box(0, 1.38, -0.55, 0.72, 0.46, 0.75, kBody, top: kBodyDark);
    m.box(0, 1.89, -0.55, 0.8, 0.06, 0.85, kBodyDark); // roof
    m.box(0, 1.98, -0.55, 0.6, 0.04, 0.65, gold, flags: kDecal);
    for (final sx in [-0.722, 0.722]) {
      m.box(sx, 1.5, -0.55, 0.004, 0.2, 0.4, 0xFF1C2A3A, flags: kDecal); // side windows
      m.box(sx, 1.18, -0.55, 0.006, 0.03, 0.72, gold, flags: kDecal); // trim
    }
    m.box(0, 1.5, -1.302, 0.42, 0.18, 0.004, 0xFF1C2A3A, flags: kDecal); // rear window
    // coachman bench and driver
    m.box(0, 1.25, 0.5, 0.55, 0.08, 0.3, wood);
    _driver(m, 0.5, 1.33);
    // lanterns (front, warm) and tail lamps (rear, red)
    for (final sx in [-0.78, 0.78]) {
      m.box(sx, 1.75, 0.22, 0.07, 0.1, 0.07, 0xFFFFE9A8, flags: kEmissive);
      m.box(sx * 0.8, 1.0, -1.32, 0.08, 0.06, 0.02, 0xFFFF2233, flags: kEmissive);
    }
    // shafts out to the horse
    for (final sx in [-0.42, 0.42]) {
      m.box(sx, 1.05, 1.75, 0.03, 0.03, 1.15, wood);
    }
    _horse(m, 2.55, t);
    return m;
  });

  /// Slow traffic: an open farm cart with hay, pulled by a plodding horse.
  static final List<Mesh> cart = List.generate(frames, (f) {
    final m = Mesh();
    final t = f / frames;
    const wood = 0xFF8A5A32, dark = 0xFF5A3A20;
    for (final wx in [-0.8, 0.8]) {
      m.spokedWheel(wx, 0.6, -0.4, 0.6, t * math.pi / 3, dark, 0xFFB08050);
    }
    m.box(0, 0.6, -0.4, 0.78, 0.03, 0.03, dark);
    m.box(0, 0.95, -0.4, 0.7, 0.08, 1.0, wood);
    for (final sx in [-0.68, 0.68]) {
      m.box(sx, 1.25, -0.4, 0.03, 0.25, 1.0, dark);
    }
    m.box(0, 1.25, -1.38, 0.68, 0.25, 0.03, dark);
    m.box(0, 1.35, -0.55, 0.6, 0.25, 0.7, 0xFFE3C15A); // hay
    m.box(0, 1.2, 0.5, 0.45, 0.06, 0.2, dark);
    _driver(m, 0.5, 1.26);
    for (final sx in [-0.4, 0.4]) {
      m.box(sx, 1.0, 1.5, 0.03, 0.03, 0.95, dark);
    }
    _horse(m, 2.25, t);
    return m;
  });

  static final Mesh lamp = () {
    final m = Mesh();
    m.box(0, 4.5, 0, 0.09, 4.5, 0.09, 0xFF5E606C);
    m.box(-0.9, 8.95, 0, 0.9, 0.06, 0.07, 0xFF5E606C); // arm reaches toward the road (-x)
    m.box(-1.7, 8.85, 0, 0.3, 0.07, 0.16, 0xFFFFF1C2, flags: kEmissive);
    return m;
  }();

  static final List<Mesh> palm = List.generate(2, (variant) {
    final m = Mesh();
    // segmented, slightly bending trunk
    var x = 0.0;
    const segs = 6;
    for (var i = 0; i < segs; i++) {
      final nx = x + (variant == 0 ? 0.12 : -0.1) * i;
      m.box(nx, 0.9 + i * 1.6, 0, 0.22 - i * 0.015, 0.82, 0.22 - i * 0.015, i.isEven ? 0xFF7A5230 : 0xFF6A4628);
      x = nx;
    }
    final top = [x, segs * 1.6 + 0.3, 0.0];
    for (var i = 0; i < 8; i++) {
      final a = i / 8 * math.pi * 2 + variant * 0.3;
      final dx = math.cos(a), dz = math.sin(a);
      final mid = [top[0] + dx * 2.0, top[1] + 0.6, top[2] + dz * 2.0];
      final tip = [top[0] + dx * 4.0, top[1] - 1.2, top[2] + dz * 4.0];
      final sideX = -dz * 0.6, sideZ = dx * 0.6;
      final col = i.isEven ? 0xFF2E8B3E : 0xFF237331;
      m.tri(top, [mid[0] + sideX, mid[1], mid[2] + sideZ], mid, col, center: [top[0], top[1] - 5, top[2]], flags: kTwoSided);
      m.tri(top, mid, [mid[0] - sideX, mid[1], mid[2] - sideZ], col, center: [top[0], top[1] - 5, top[2]], flags: kTwoSided);
      m.tri([mid[0] + sideX, mid[1], mid[2] + sideZ], tip, mid, col, center: [top[0], top[1] - 5, top[2]], flags: kTwoSided);
      m.tri(mid, tip, [mid[0] - sideX, mid[1], mid[2] - sideZ], col, center: [top[0], top[1] - 5, top[2]], flags: kTwoSided);
    }
    return m;
  });

  static final Mesh pine = () {
    final m = Mesh();
    m.box(0, 0.8, 0, 0.25, 0.8, 0.25, 0xFF5A3A22);
    for (var i = 0; i < 3; i++) {
      m.cone(0, 1.4 + i * 2.2, 0, 2.6 - i * 0.7, 3.4 - i * 0.5, 7, i == 2 ? 0xFFE9F0F7 : 0xFF1E5A3A,
          bottom: 0xFF16452C);
    }
    return m;
  }();

  static final List<Mesh> rock = List.generate(3, (seed) {
    final m = Mesh();
    final r = math.Random(seed + 11);
    final pts = List.generate(7, (i) {
      final a = i / 7 * math.pi * 2;
      return [math.cos(a) * (0.8 + r.nextDouble() * 0.4), 0.0, math.sin(a) * (0.8 + r.nextDouble() * 0.4)];
    });
    final top = [r.nextDouble() * 0.3, 1.0, r.nextDouble() * 0.3];
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      final mid = [(a[0] + top[0]) * 0.6, 0.55 + r.nextDouble() * 0.15, (a[2] + top[2]) * 0.6];
      m.tri(a, b, mid, 0xFFFFFFFF, center: [0, 0.3, 0]);
      m.tri(mid, b, top, 0xFFFFFFFF, center: [0, 0.3, 0]);
    }
    return m; // tinted per location at draw time
  });

  static final List<Mesh> umbrella = [0xFFFF4D4D, 0xFF2F8CFF].map((stripe) {
    final m = Mesh();
    m.box(0, 1.2, 0, 0.04, 1.2, 0.04, 0xFFEEEEEE);
    const sides = 10;
    for (var i = 0; i < sides; i++) {
      final a1 = i / sides * math.pi * 2, a2 = (i + 1) / sides * math.pi * 2;
      m.tri([math.cos(a1) * 1.6, 2.1, math.sin(a1) * 1.6], [math.cos(a2) * 1.6, 2.1, math.sin(a2) * 1.6],
          [0, 2.7, 0], i.isEven ? stripe : 0xFFFFFFFF,
          center: [0, 0, 0], flags: kTwoSided);
    }
    return m;
  }).toList();

  /// Unit-ish tower block (1 x 1 x 1 at the base, scaled per instance) with lit-window patterns.
  static final List<Mesh> building = List.generate(3, (seed) {
    final m = Mesh();
    // walls take the location's building colour (kBody), windows its window colour (kCoat)
    m.box(0, 0.5, 0, 0.5, 0.5, 0.5, kBody, top: kBodyDark);
    final r = math.Random(seed * 31 + 7);
    for (final face in [-1, 1]) {
      for (var row = 0; row < 12; row++) {
        for (var col = 0; col < 4; col++) {
          if (r.nextDouble() > 0.35) continue;
          final y = 0.06 + row * 0.075, z = -0.36 + col * 0.24;
          // windows on the two faces that look along the road (±x)
          m.box(face * 0.502, y, z, 0.002, 0.022, 0.06, kCoat, flags: kEmissive | kDecal);
        }
      }
    }
    return m;
  });

  /// Mud-brick kasbah, base 1 x 1, scaled per instance.
  static final Mesh kasbah = () {
    final m = Mesh();
    const wall = 0xFFB8673E, dark = 0xFF3A1E12;
    m.box(0, 0.36, 0, 0.5, 0.36, 0.45, wall);
    for (final tx in [-0.4, 0.4]) {
      for (final tz in [-0.35, 0.35]) {
        m.box(tx, 0.5, tz, 0.12, 0.5, 0.12, wall);
        m.box(tx, 1.03, tz, 0.13, 0.03, 0.13, 0xFFA65A34);
      }
    }
    for (final face in [-1.0, 1.0]) {
      m.box(face * 0.501, 0.13, 0, 0.002, 0.13, 0.08, dark, flags: kDecal);
      for (var i = -1; i <= 1; i++) {
        m.box(face * 0.501, 0.5, i * 0.18, 0.002, 0.05, 0.03, dark, flags: kDecal);
      }
    }
    return m;
  }();

  /// Road-spanning gantry. [chequered] = start/finish, otherwise a sign board (text drawn separately).
  static Mesh gantry(bool chequered) {
    final m = Mesh();
    const post = 0xFF8A8A99;
    for (final x in [-7.6, 7.6]) {
      m.box(x, 3.6, 0, 0.18, 3.6, 0.18, post);
    }
    if (chequered) {
      const cols = 16, rows = 3;
      const w = 15.6 / cols, h = 1.8 / rows;
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final x0 = -7.8 + c * w, y0 = 7.2 + r * h;
          final col = (r + c).isEven ? 0xFFFFFFFF : 0xFF111111;
          m.quad([x0, y0, 0], [x0 + w, y0, 0], [x0 + w, y0 + h, 0], [x0, y0 + h, 0], col,
              center: [0, 8, 1], flags: kTwoSided);
        }
      }
    } else {
      m.box(0, 8.1, 0, 7.8, 1.0, 0.12, 0xFF0D0A1F);
      m.box(0, 9.12, 0, 7.8, 0.05, 0.14, 0xFFFF3D7F, flags: kEmissive);
      m.box(0, 7.08, 0, 7.8, 0.05, 0.14, 0xFFFF3D7F, flags: kEmissive);
    }
    return m;
  }

  static final Mesh signGantry = gantry(false);
  static final Mesh finishGantry = gantry(true);
}

/// Exposed for the renderer.
int shade(int argb, double k) => _shade(argb, k);
