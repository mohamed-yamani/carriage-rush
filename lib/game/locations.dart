import 'package:flutter/painting.dart';

enum FarLayer { city, dunes, mountains, sea }

enum Prop { lamp, building, palm, rock, kasbah, pine, umbrella }

/// Carriage-era road surfaces.
enum RoadStyle { cobble, sand, gravel, paving }

/// Everything that makes one place look and drive differently.
class Location {
  const Location({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.night,
    required this.sky,
    required this.fog,
    required this.groundLight,
    required this.groundDark,
    required this.roadLight,
    required this.roadDark,
    required this.rumbleA,
    required this.rumbleB,
    required this.lane,
    required this.far,
    required this.farA,
    required this.farB,
    required this.sunColor,
    required this.sunHeight,
    required this.curviness,
    required this.hilliness,
    required this.traffic,
    required this.props,
    required this.seed,
    required this.road,
    required this.dust,
    required this.ambient,
  });

  final String id, name, subtitle;
  final bool night;
  final List<Color> sky; // top, middle, horizon
  final Color fog, groundLight, groundDark, roadLight, roadDark, rumbleA, rumbleB, lane;
  final FarLayer far;
  final Color farA, farB; // far silhouette colours (back, front)
  final Color sunColor; // moon at night
  final double sunHeight; // 0 = on the horizon, 1 = top of the sky
  final double curviness, hilliness;
  final int traffic;
  final Map<Prop, double> props; // prop -> chance per roadside slot
  final int seed;
  final RoadStyle road;
  final Color dust; // what the wheels kick up off the road
  final String ambient; // looping background sound
}

const locations = <Location>[
  Location(
    id: 'casablanca',
    name: 'CASABLANCA',
    subtitle: 'City lights at midnight',
    night: true,
    sky: [Color(0xFF03030C), Color(0xFF120A2E), Color(0xFF1A1035)],
    fog: Color(0xFF1A1035),
    groundLight: Color(0xFF0E2618),
    groundDark: Color(0xFF0B1F14),
    roadLight: Color(0xFF4A4650),
    roadDark: Color(0xFF3F3B45),
    rumbleA: Color(0xFF8E8A92),
    rumbleB: Color(0xFF6E6A74),
    lane: Color(0xFFF2F0E6),
    far: FarLayer.city,
    farA: Color(0xFF0B0820),
    farB: Color(0xFF15122A),
    sunColor: Color(0xFFFFF4D6),
    sunHeight: 0.7,
    curviness: 1.0,
    hilliness: 0.6,
    traffic: 10,
    props: {Prop.lamp: 1, Prop.building: 0.7},
    seed: 1337,
    road: RoadStyle.cobble,
    dust: Color(0xFF8C8478),
    ambient: 'crickets',
  ),
  Location(
    id: 'sahara',
    name: 'SAHARA',
    subtitle: 'Sunset over the dunes',
    night: false,
    sky: [Color(0xFF2B1A4A), Color(0xFFE0566B), Color(0xFFFFB259)],
    fog: Color(0xFFF2A35E),
    groundLight: Color(0xFFE8B26A),
    groundDark: Color(0xFFDDA45C),
    roadLight: Color(0xFFC99A5E),
    roadDark: Color(0xFFBE8F54),
    rumbleA: Color(0xFFD8B27A),
    rumbleB: Color(0xFFB88A55),
    lane: Color(0xFFF7EEDD),
    far: FarLayer.dunes,
    farA: Color(0xFFC77A4A),
    farB: Color(0xFFD9925A),
    sunColor: Color(0xFFFFE08A),
    sunHeight: 0.12,
    curviness: 0.6,
    hilliness: 1.6,
    traffic: 3,
    props: {Prop.palm: 0.25, Prop.rock: 0.35, Prop.kasbah: 0.12},
    seed: 2026,
    road: RoadStyle.sand,
    dust: Color(0xFFE9BF7E),
    ambient: 'wind',
  ),
  Location(
    id: 'atlas',
    name: 'ATLAS',
    subtitle: 'Snowy mountain pass',
    night: false,
    sky: [Color(0xFF3F7CC9), Color(0xFF8DBDEB), Color(0xFFDCEBF7)],
    fog: Color(0xFFDCEBF7),
    groundLight: Color(0xFFF4F7FB),
    groundDark: Color(0xFFE6ECF4),
    roadLight: Color(0xFF8A8278),
    roadDark: Color(0xFF7E766C),
    rumbleA: Color(0xFFA9A49C),
    rumbleB: Color(0xFF8C877F),
    lane: Color(0xFFFFFFFF),
    far: FarLayer.mountains,
    farA: Color(0xFF7D93B5),
    farB: Color(0xFF5E7598),
    sunColor: Color(0xFFFFFBE8),
    sunHeight: 0.75,
    curviness: 1.6,
    hilliness: 1.3,
    traffic: 4,
    props: {Prop.pine: 0.8, Prop.rock: 0.15},
    seed: 4165,
    road: RoadStyle.gravel,
    dust: Color(0xFFE9EEF5),
    ambient: 'mountain',
  ),
  Location(
    id: 'agadir',
    name: 'AGADIR',
    subtitle: 'Sunny ocean highway',
    night: false,
    sky: [Color(0xFF1E8FE0), Color(0xFF6CC4F5), Color(0xFFC9ECFF)],
    fog: Color(0xFFC9ECFF),
    groundLight: Color(0xFFF0D9A8),
    groundDark: Color(0xFFE8CE98),
    roadLight: Color(0xFFD9C7A8),
    roadDark: Color(0xFFC7B08C),
    rumbleA: Color(0xFFEDE3D0),
    rumbleB: Color(0xFFB89A70),
    lane: Color(0xFFFFFFFF),
    far: FarLayer.sea,
    farA: Color(0xFF1767B8),
    farB: Color(0xFF3B9BE0),
    sunColor: Color(0xFFFFF6C9),
    sunHeight: 0.8,
    curviness: 0.8,
    hilliness: 0.5,
    traffic: 6,
    props: {Prop.palm: 0.7, Prop.umbrella: 0.35, Prop.lamp: 0.3},
    seed: 8000,
    road: RoadStyle.paving,
    dust: Color(0xFFF0D9A8),
    ambient: 'waves',
  ),
];
