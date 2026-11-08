import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'game.dart';

/// Plays the game's sounds: one-shot effects from small pools, plus looping layers
/// (your horse's hooves, the pack around you, gravel off-road, and the location's ambience)
/// whose speed and volume follow the race.
class SoundEngine {
  SoundEngine(this.game);

  final Game game;
  bool _ready = false;
  final Map<Sfx, AudioPool> _pools = {};
  final _gallop = AudioPlayer();
  final _pack = AudioPlayer();
  final _gravel = AudioPlayer();
  final _ambient = AudioPlayer();
  String? _ambientName;
  double _sinceSync = 1;
  final Map<AudioPlayer, double> _volumes = {};
  double _rate = 1;

  /// Audio plugins are not available inside `flutter test`.
  static bool get _available => !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

  static const _files = {
    Sfx.beep: 'sfx/beep.wav',
    Sfx.go: 'sfx/go.wav',
    Sfx.neigh: 'sfx/neigh.wav',
    Sfx.crash: 'sfx/crash.wav',
    Sfx.bump: 'sfx/bump.wav',
    Sfx.rock: 'sfx/rock.wav',
    Sfx.fanfare: 'sfx/fanfare.wav',
    Sfx.click: 'sfx/click.wav',
    Sfx.whip: 'sfx/whip.wav',
  };
  static const _volume = {
    Sfx.beep: 0.6,
    Sfx.go: 0.8,
    Sfx.neigh: 0.7,
    Sfx.crash: 1.0,
    Sfx.bump: 0.8,
    Sfx.rock: 1.0,
    Sfx.fanfare: 0.8,
    Sfx.click: 0.4,
    Sfx.whip: 0.45,
  };

  Future<void> init() async {
    if (!_available) return;
    try {
      // let every layer play at once
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
      for (final e in _files.entries) {
        _pools[e.key] = await AudioPool.createFromAsset(path: e.value, maxPlayers: 3);
      }
      for (final (p, file) in [
        (_gallop, 'sfx/gallop.wav'),
        (_pack, 'sfx/pack.wav'),
        (_gravel, 'sfx/gravel.wav'),
      ]) {
        await p.setReleaseMode(ReleaseMode.loop);
        await p.setVolume(0);
        await p.play(AssetSource(file), volume: 0);
        _volumes[p] = 0;
      }
      await _ambient.setReleaseMode(ReleaseMode.loop);
      _ready = true;
    } catch (e) {
      debugPrint('sound disabled: $e');
    }
  }

  /// Call every frame.
  void update(double dt) {
    if (!_ready) {
      game.sounds.clear();
      return;
    }
    for (final s in game.sounds) {
      if (!game.muted && !game.adShowing) _pools[s]?.start(volume: _volume[s] ?? 1);
    }
    game.sounds.clear();

    // loop parameters change slowly; don't flood the platform channel every frame
    _sinceSync += dt;
    if (_sinceSync < 0.1) return;
    _sinceSync = 0;

    final racing = game.phase == Phase.racing || game.phase == Phase.finished || game.phase == Phase.countdown;
    final speed = game.player.speed;
    final mute = game.muted || game.adShowing || game.phase == Phase.paused;

    // hooves: the loop is recorded at 2 strides/s, so play it back at the horse's cadence
    final cadence = Game.strideRate(speed);
    _setVolume(_gallop, mute || cadence == 0 ? 0 : (racing ? 0.9 : 0.35));
    if (cadence > 0) {
      final rate = (cadence / 2.0).clamp(0.5, 2.0);
      if ((rate - _rate).abs() > 0.04) {
        _rate = rate;
        _gallop.setPlaybackRate(rate);
      }
    }
    _setVolume(_pack, mute || !racing ? 0 : (game.nearbyRivals / 5).clamp(0.0, 1.0) * 0.55);
    _setVolume(_gravel, mute || !racing ? 0 : game.rumble * 0.8);

    final want = game.location.ambient;
    if (want != _ambientName) {
      _ambientName = want;
      _ambient.play(AssetSource('sfx/$want.wav'), volume: mute ? 0 : 0.45);
      _volumes[_ambient] = mute ? 0 : 0.45;
    }
    _setVolume(_ambient, mute ? 0 : 0.45);
  }

  void _setVolume(AudioPlayer p, double v) {
    if (((_volumes[p] ?? -1) - v).abs() < 0.02) return;
    _volumes[p] = v;
    p.setVolume(v);
  }

  void dispose() {
    for (final p in [_gallop, _pack, _gravel, _ambient]) {
      p.dispose();
    }
    for (final pool in _pools.values) {
      pool.dispose();
    }
  }
}
