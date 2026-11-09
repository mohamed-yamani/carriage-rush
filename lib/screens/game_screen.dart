import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../ads/ads.dart';
import '../game/countries.dart';
import '../game/game.dart';
import '../game/locations.dart';
import '../game/painter3d.dart';
import '../game/sound.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  final Game game = Game();
  late final SoundEngine _sound = SoundEngine(game);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final Map<int, _Touch> _touches = {};
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 20);
      _last = elapsed;
      game.update(dt);
      _sound.update(dt);
    })
      ..start();
    _sound.init();
    // consent + ads after the first frame, so the consent form has a screen to sit on
    // `--dart-define=NOADS=true` skips consent + ads entirely (clean store screenshots)
    if (!const bool.fromEnvironment('NOADS')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Ads.instance.init());
    }
    // `--dart-define=AUTOSTART=true [--dart-define=LOCATION=1]` jumps straight into a race (screenshots/testing)
    game.selectLocation(const int.fromEnvironment('LOCATION'));
    if (const bool.fromEnvironment('AUTOSTART')) game.startRace();
    // `--dart-define=OFFROAD=true` keeps steering right so the verge effects can be screenshotted
    if (const bool.fromEnvironment('OFFROAD')) game.steerRight = true;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sound.dispose();
    game.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------- input: hold left/right half of the screen to steer ----------
  void _syncTouches() {
    game.steerLeft = _touches.values.any((t) => t == _Touch.left);
    game.steerRight = _touches.values.any((t) => t == _Touch.right);
  }

  void _down(PointerDownEvent e, double width) {
    _touches[e.pointer] = e.localPosition.dx < width / 2 ? _Touch.left : _Touch.right;
    _syncTouches();
  }

  void _up(PointerEvent e) {
    _touches.remove(e.pointer);
    _syncTouches();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final down = e is! KeyUpEvent;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
      game.steerLeft = down;
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
      game.steerRight = down;
    } else if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) {
      game.braking = down;
    } else if (k == LogicalKeyboardKey.space && e is KeyDownEvent) {
      if (game.phase == Phase.menu || game.phase == Phase.finished) game.startRace();
    } else if (k == LogicalKeyboardKey.keyP && e is KeyDownEvent) {
      game.togglePause();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, c) => Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                onPointerDown: (e) => _down(e, c.maxWidth),
                onPointerUp: _up,
                onPointerCancel: _up,
                child: RepaintBoundary(child: CustomPaint(painter: RacePainter(game))),
              ),
              ListenableBuilder(
                listenable: game,
                builder: (context, _) => switch (game.phase) {
                  Phase.menu => game.profileLoaded && !game.hasProfile ? _Welcome(game: game) : _Menu(game: game),
                  Phase.finished => _Results(game: game),
                  _ => _Hud(game: game),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Touch { left, right }

// ---------- shared bits ----------
const _neonPink = Color(0xFFFF3D7F);
const _gold = Color(0xFFFFD447);

String ordinal(int n) => '$n${switch (n) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' }}';

class _NameTitle extends StatelessWidget {
  const _NameTitle({this.size = 64, this.text = 'CARRIAGE RUSH'});
  final double size;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(colors: [_gold, Color(0xFFFF8A3D), _neonPink]).createShader(r),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          letterSpacing: size * 0.12,
          color: Colors.white,
          shadows: const [Shadow(color: _neonPink, blurRadius: 24)],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(12)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: child,
      );
}

// ---------- menu: pick a place, then race ----------
class _Menu extends StatelessWidget {
  const _Menu({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final loc = game.location;
    final bestTime = game.bestTimes[loc.id];
    final bestPlace = game.bestPlaces[loc.id];
    final pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(game.time * 4));
    return Container(
      color: Colors.black.withValues(alpha: 0.25),
      child: SafeArea(
        // fills tall screens (the Spacer pushes the title up), scrolls on short ones instead of overflowing
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 8),
                _ProfileChip(game: game),
                const SizedBox(width: 6),
                _CoinChip(coins: game.coins),
                const Spacer(),
                _MuteButton(game: game),
              ],
            ),
            const FittedBox(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: _NameTitle(text: 'CARRIAGE\nRUSH', size: 60),
              ),
            ),
            const SizedBox(height: 4),
            const Text('H O R S E   R A C E',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 2)),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    game.sfx(Sfx.click);
                    game.selectLocation(game.locationIndex - 1 + locations.length);
                  },
                  icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 40),
                ),
                Expanded(
                  child: _Panel(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                    child: Column(
                      children: [
                        FittedBox(
                          child: Text(loc.name,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4)),
                        ),
                        Text('${flagOf(loc.country)}  ${loc.subtitle}',
                            style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < locations.length; i++)
                              Container(
                                width: i == game.locationIndex ? 18 : 7,
                                height: 7,
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  color: i == game.locationIndex ? _gold : Colors.white30,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          bestTime == null
                              ? 'No record yet'
                              : '${game.medalFor(loc.id)}  BEST  ${formatTime(bestTime)}   •   TOP ${ordinal(bestPlace ?? 10)}'.trim(),
                          style: const TextStyle(color: _gold, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    game.sfx(Sfx.click);
                    game.selectLocation(game.locationIndex + 1);
                  },
                  icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 40),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DifficultyPicker(game: game),
            const SizedBox(height: 16),
            Opacity(
              opacity: pulse,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _neonPink,
                  padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 18),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => _startWithAd(game),
                child: const Text('RACE', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              game.startPosition == 1
                  ? 'You start 1st — you won last race!'
                  : 'You start ${ordinal(game.startPosition)} on the grid',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            if (game.startPosition > 1) _PoleButton(game: game, label: 'Start from POLE'),
            TextButton.icon(
              onPressed: () => _openGarage(context, game),
              icon: const Icon(Icons.storefront_rounded, color: _gold),
              label: const Text('GARAGE', style: TextStyle(color: _gold, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ),
            const SizedBox(height: 6),
            const Text('You vs 9 rivals • start last, finish first\nHold left / right side to steer • BRAKE to slow',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
            ValueListenableBuilder(
              valueListenable: Ads.instance.privacyOptionsRequired,
              builder: (context, required, _) => required
                  ? TextButton(
                      onPressed: Ads.instance.showPrivacyOptions,
                      child: const Text('Privacy settings', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    )
                  : const SizedBox(height: 12),
            ),
            const BannerAdBox(),
          ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- in-race HUD ----------
class _Hud extends StatelessWidget {
  const _Hud({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final place = game.placeOf(game.player);
    final standings = game.standings();
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            left: 14,
            top: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$place',
                        style: TextStyle(
                            color: place <= 3 ? _gold : Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            height: 1)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(' / ${game.racers.length}',
                          style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const Text('POSITION', style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 2)),
                const SizedBox(height: 8),
                _Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < math.min(4, standings.length); i++) _LeaderRow(pos: i + 1, racer: standings[i]),
                      if (place > 4) ...[
                        const Text('  ···', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        _LeaderRow(pos: place, racer: game.player),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(right: 48, top: 0, child: _MuteButton(game: game)),
          Positioned(
            right: 6,
            top: 0,
            child: IconButton(
              onPressed: game.togglePause,
              icon: Icon(game.phase == Phase.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: Colors.white, size: 32),
            ),
          ),
          Positioned(
            right: 16,
            top: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatTime(game.raceTime),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(height: 6),
                Text('${game.kmh}',
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1)),
                const Text('KM/H', style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 2)),
              ],
            ),
          ),
          Positioned(left: 16, right: 16, bottom: 128, child: _ProgressBar(game: game)),
          if (game.offRoad)
            const Align(
              alignment: Alignment(0, -0.35),
              child: Text('OFF ROAD',
                  style: TextStyle(color: _gold, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3)),
            ),
          if (game.crashFlash > 0)
            const Align(
              alignment: Alignment(0, -0.15),
              child: Text('CRASH!', style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900)),
            ),
          if (game.phase == Phase.countdown)
            Align(
              alignment: const Alignment(0, -0.2),
              child: Text(
                '${game.countdown.ceil()}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 120 + 40 * (game.countdown % 1),
                  fontWeight: FontWeight.w900,
                  shadows: const [Shadow(color: _neonPink, blurRadius: 30)],
                ),
              ),
            ),
          if (game.phase == Phase.racing && game.raceTime < 0.8)
            const Align(
              alignment: Alignment(0, -0.2),
              child: Text('GO!',
                  style: TextStyle(
                      color: _gold,
                      fontSize: 110,
                      fontWeight: FontWeight.w900,
                      shadows: [Shadow(color: _neonPink, blurRadius: 30)])),
            ),
          if (game.phase == Phase.paused)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('PAUSED',
                      style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 6)),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _neonPink, shape: const StadiumBorder()),
                    onPressed: game.togglePause,
                    child: const Text('RESUME', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2)),
                  ),
                  TextButton(
                    onPressed: game.toMenu,
                    child: const Text('QUIT TO MENU', style: TextStyle(color: Colors.white70, letterSpacing: 2)),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Listener(
                onPointerDown: (_) => game.braking = true,
                onPointerUp: (_) => game.braking = false,
                onPointerCancel: (_) => game.braking = false,
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: game.braking ? _neonPink.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.25),
                    border: Border.all(color: Colors.white54, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: const Text('BRAKE',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
              ),
            ),
          ),
          if (const bool.fromEnvironment('SHOWFPS'))
            Positioned(
              left: 12,
              bottom: 8,
              child: Text(
                  '${RacePainter.lastPaintMs.toStringAsFixed(1)} ms • ${RacePainter.lastTriangles} tris',
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

/// EASY / NORMAL / HARD, remembered between launches.
class _DifficultyPicker extends StatelessWidget {
  const _DifficultyPicker({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) => SegmentedButton<Difficulty>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          foregroundColor: Colors.white70,
          selectedForegroundColor: Colors.black,
          selectedBackgroundColor: _gold,
          backgroundColor: Colors.black.withValues(alpha: 0.4),
          side: const BorderSide(color: Colors.white24),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 13),
        ),
        segments: [
          for (final d in Difficulty.values) ButtonSegment(value: d, label: Text(d.label)),
        ],
        selected: {game.difficulty},
        onSelectionChanged: (s) => game.setDifficulty(s.first),
      );
}

// ---------- player profile ----------
/// Tappable "🇧🇷 LUCAS" chip on the menu that reopens the profile editor.
class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) => ActionChip(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        side: const BorderSide(color: Colors.white24),
        shape: const StadiumBorder(),
        avatar: Text(game.player.flag.isEmpty ? '🏁' : game.player.flag, style: const TextStyle(fontSize: 16)),
        label: Text(game.playerName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1)),
        onPressed: () {
          game.sfx(Sfx.click);
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: const Color(0xFF15122A),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (context) => Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: _ProfileEditor(game: game, onSaved: () => Navigator.of(context).pop()),
            ),
          );
        },
      );
}

/// First launch: say hello and ask who is racing.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FittedBox(child: _NameTitle(text: 'CARRIAGE\nRUSH', size: 52)),
                  const SizedBox(height: 18),
                  _Panel(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                    child: _ProfileEditor(game: game, title: 'WELCOME, RACER!'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Name + country form, used on first launch and from the menu chip.
class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.game, this.onSaved, this.title = 'YOUR RACER'});
  final Game game;
  final VoidCallback? onSaved;
  final String title;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final TextEditingController _name;
  Country? _country;

  @override
  void initState() {
    super.initState();
    final g = widget.game;
    _name = TextEditingController(text: g.hasProfile ? g.playerName : '');
    // guess the country from the phone's region the first time
    _country = countryByCode(g.playerCountry) ??
        countryByCode(WidgetsBinding.instance.platformDispatcher.locale.countryCode);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().length >= 2 && _country != null;

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15122A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => const _CountryPicker(),
    );
    if (picked != null) setState(() => _country = picked);
  }

  void _save() {
    if (!_valid) return;
    widget.game.sfx(Sfx.click);
    widget.game.setProfile(_name.text, _country!.code);
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: !widget.game.hasProfile,
              maxLength: 12,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[\p{L}\p{N} ._'-]", unicode: true))],
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1),
              decoration: const InputDecoration(
                labelText: 'Your name',
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                side: const BorderSide(color: Colors.white38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.centerLeft,
              ),
              onPressed: _pickCountry,
              child: Row(
                children: [
                  Text(_country?.flag ?? '🌍', style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_country?.name ?? 'Choose your country',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const Icon(Icons.expand_more_rounded, color: Colors.white70),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _neonPink,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const StadiumBorder(),
              ),
              onPressed: _valid ? _save : null,
              child: const Text("LET'S RACE", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ),
          ],
        ),
      );
}

/// Searchable list of every country.
class _CountryPicker extends StatefulWidget {
  const _CountryPicker();

  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final list = countries.where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.code.toLowerCase() == q).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search country',
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) => ListTile(
                  leading: Text(list[i].flag, style: const TextStyle(fontSize: 26)),
                  title: Text(list[i].name, style: const TextStyle(color: Colors.white)),
                  onTap: () => Navigator.of(context).pop(list[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MuteButton extends StatelessWidget {
  const _MuteButton({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: game.toggleMute,
        tooltip: game.muted ? 'Sound on' : 'Mute',
        icon: Icon(game.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white, size: 28),
      );
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.pos, required this.racer});
  final int pos;
  final Racer racer;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 18,
                child: Text('$pos',
                    style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w700))),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: Color(racer.color), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('${racer.flag} ${racer.name}'.trim(),
                style: TextStyle(
                    color: racer.isPlayer ? _gold : Colors.white,
                    fontSize: 12,
                    fontWeight: racer.isPlayer ? FontWeight.w900 : FontWeight.w600)),
          ],
        ),
      );
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        // draw the player last so their dot sits on top
        final dots = [...game.racers.where((r) => !r.isPlayer), game.player];
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 9,
              child: Container(
                  height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            ),
            Positioned(
              left: 0,
              top: 9,
              child: Container(
                  height: 4,
                  width: w * game.progressOf(game.player),
                  decoration: BoxDecoration(color: _neonPink, borderRadius: BorderRadius.circular(2))),
            ),
            const Positioned(right: -4, top: 2, child: Icon(Icons.flag_rounded, color: Colors.white, size: 18)),
            for (final r in dots)
              Positioned(
                left: w * game.progressOf(r) - (r.isPlayer ? 7 : 4),
                top: r.isPlayer ? 4 : 7,
                child: Container(
                  width: r.isPlayer ? 14 : 8,
                  height: r.isPlayer ? 14 : 8,
                  decoration: BoxDecoration(
                    color: Color(r.color),
                    shape: BoxShape.circle,
                    border: r.isPlayer ? Border.all(color: Colors.white, width: 2) : null,
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

// ---------- results ----------
class _Results extends StatelessWidget {
  const _Results({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final rows = game.results();
    final place = rows.indexWhere((r) => r.racer.isPlayer) + 1;
    final winner = rows.first.time;
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: Stack(
        children: [
          if (place == 1) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Confetti(game.time)))),
          SafeArea(
            child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (place == 1) const Text('🏆', style: TextStyle(fontSize: 52)),
                Text(place == 1 ? 'YOU WIN!' : 'FINISHED',
                    style: TextStyle(
                        color: place == 1 ? _gold : Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4)),
                Text('${ordinal(place)} place  •  ${game.location.name}  •  ${game.difficulty.label}',
                    style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w700)),
                if (game.newBest)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('NEW BEST TIME!',
                        style: TextStyle(color: _neonPink, fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                const SizedBox(height: 10),
                _CoinsEarned(game: game),
                // actions first, so they are on screen without scrolling; the full table follows
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _neonPink,
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => _startWithAd(game),
                  child: const Text('RACE AGAIN',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    place == 1 ? 'Next race you start on POLE' : 'Next race you start ${ordinal(place)}',
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                  ),
                ),
                if (place > 1) _PoleButton(game: game, label: 'Retry from POLE'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () {
                        game.selectLocation(game.locationIndex + 1);
                        _startWithAd(game);
                      },
                      child: Text('NEXT: ${locations[(game.locationIndex + 1) % locations.length].name}',
                          style: const TextStyle(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.w700)),
                    ),
                    TextButton(
                      onPressed: game.toMenu,
                      child: const Text('MENU', style: TextStyle(color: Colors.white70, letterSpacing: 2)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _Panel(
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                          decoration: BoxDecoration(
                            color: rows[i].racer.isPlayer ? _neonPink.withValues(alpha: 0.25) : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 30,
                                child: Text('${i + 1}',
                                    style: TextStyle(
                                        color: i < 3 ? _gold : Colors.white70,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15)),
                              ),
                              Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(color: Color(rows[i].racer.color), shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('${rows[i].racer.flag} ${rows[i].racer.name}'.trim(),
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: rows[i].racer.isPlayer ? FontWeight.w900 : FontWeight.w600)),
                              ),
                              Text(
                                i == 0
                                    ? formatTime(rows[i].time)
                                    : '+${(rows[i].time - winner).toStringAsFixed(2)}${rows[i].estimated ? '*' : ''}',
                                style: const TextStyle(color: Colors.white70, fontFeatures: [FontFeature.tabularFigures()]),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const BannerAdBox(),
              ],
            ),
          ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- rewards ----------
class _CoinChip extends StatelessWidget {
  const _CoinChip({required this.coins});
  final int coins;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withValues(alpha: 0.6)),
        ),
        child: Text('🪙 $coins', style: const TextStyle(color: _gold, fontWeight: FontWeight.w900, fontSize: 15)),
      );
}

/// "+100 🪙" for the place, the first-win bonus, and the rewarded "×2" offer.
class _CoinsEarned extends StatelessWidget {
  const _CoinsEarned({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final earned = game.raceCoins + game.raceBonus;
    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Column(
        children: [
          Text(game.coinsDoubled ? '+${earned * 2} 🪙  (doubled!)' : '+$earned 🪙',
              style: const TextStyle(color: _gold, fontSize: 26, fontWeight: FontWeight.w900)),
          if (game.raceBonus > 0)
            Text('includes +${game.raceBonus} for your first win in ${game.location.name}!',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text('Total: ${game.coins} 🪙', style: const TextStyle(color: Colors.white, fontSize: 13)),
          if (!game.coinsDoubled && earned > 0)
            ValueListenableBuilder(
              valueListenable: Ads.instance.rewardedReady,
              builder: (context, ready, _) => !ready
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _gold,
                          side: const BorderSide(color: _gold, width: 1.5),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () {
                          game.sfx(Sfx.click);
                          Ads.instance.showRewarded(
                            onShow: () => game.adShowing = true,
                            onClose: () => game.adShowing = false,
                            onReward: game.doubleRaceCoins,
                          );
                        },
                        icon: const Icon(Icons.ondemand_video_rounded, size: 20),
                        label: const Text('×2 COINS  •  watch ad',
                            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Falling confetti for a win, driven by the game clock.
class _Confetti extends CustomPainter {
  _Confetti(this.t);
  final double t;
  static const _colors = [Color(0xFFFFD447), Color(0xFFFF3D7F), Color(0xFF3D8BFF), Color(0xFF33D17A), Colors.white];

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(7);
    for (var i = 0; i < 90; i++) {
      final speed = 60 + r.nextDouble() * 120;
      final x0 = r.nextDouble() * size.width;
      final phase = r.nextDouble() * 10;
      final y = (r.nextDouble() * size.height + t * speed) % (size.height + 40) - 20;
      final x = x0 + math.sin(t * 2 + phase) * 24;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * (2 + r.nextDouble() * 3) + phase);
      canvas.drawRect(const Rect.fromLTWH(-5, -3, 10, 6), Paint()..color = _colors[i % _colors.length]);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _Confetti old) => old.t != t;
}

// ---------- garage ----------
void _openGarage(BuildContext context, Game game) {
  game.sfx(Sfx.click);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF15122A),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => ListenableBuilder(listenable: game, builder: (context, _) => _Garage(game: game)),
  );
}

class _Garage extends StatelessWidget {
  const _Garage({required this.game});
  final Game game;

  Widget _row(BuildContext context, String title, String kind, List<(int, int)> items, int selected) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (color, price) in items)
                GestureDetector(
                  onTap: () async {
                    final ok = await game.chooseItem(kind, color, price);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('You need ${price - game.coins} more 🪙 — win races to earn them!'),
                        duration: const Duration(seconds: 2),
                      ));
                    }
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Color(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: color == selected ? _gold : Colors.white24, width: color == selected ? 4 : 2),
                        ),
                        child: game.ownsItem(kind, color)
                            ? (color == selected ? const Icon(Icons.check_rounded, color: Colors.black54) : null)
                            : const Icon(Icons.lock_rounded, color: Colors.black45, size: 20),
                      ),
                      const SizedBox(height: 4),
                      Text(game.ownsItem(kind, color) ? (color == selected ? 'ON' : 'OWNED') : '🪙 $price',
                          style: TextStyle(
                              color: game.ownsItem(kind, color) ? Colors.white54 : _gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('GARAGE',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const Spacer(),
                  _CoinChip(coins: game.coins),
                ],
              ),
              const SizedBox(height: 18),
              _row(context, 'CARRIAGE PAINT', 'paint', Game.paintChoices, game.paint),
              const SizedBox(height: 20),
              _row(context, 'HORSE', 'coat', Game.coatChoices, game.coat),
            ],
          ),
        ),
      );
}

/// Opt-in rewarded ad: watch it to the end and you start the race at the front of the grid.
/// Hidden until an ad is ready, so it never leads to a dead tap.
class _PoleButton extends StatelessWidget {
  const _PoleButton({required this.game, required this.label});
  final Game game;
  final String label;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: Ads.instance.rewardedReady,
        builder: (context, ready, _) {
          if (!ready) return const SizedBox(height: 12);
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: const BorderSide(color: _gold, width: 1.5),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: () {
                game.sfx(Sfx.click);
                Ads.instance.showRewarded(
                  onShow: () => game.adShowing = true,
                  onClose: () => game.adShowing = false,
                  onReward: () => game.startRace(pole: true),
                );
              },
              icon: const Icon(Icons.ondemand_video_rounded, size: 20),
              label: Text('$label  •  watch ad', style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
          );
        },
      );
}

/// Every few races a full-screen ad plays before the countdown; the game is silent while it shows.
void _startWithAd(Game game) {
  game.sfx(Sfx.click);
  Ads.instance.betweenRaces(
    game.startRace,
    onShow: () => game.adShowing = true,
    onClose: () => game.adShowing = false,
  );
}
