import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// The orb's look. idle, live and paused are the design file's three states;
/// Listening shows the flag's red disc, thinking turns amber-red, and idle
/// and speaking use the flag green; speaking shows the clock like live.
enum OrbState { idle, live, paused, speaking }

/// The big action orb (210dp box): breathing glow, spinning sweep ring
/// (184dp, 6dp stroke, one turn per 6 s), 150dp core.
class ActionOrb extends StatefulWidget {
  const ActionOrb({
    super.key,
    required this.state,
    required this.onTap,
    this.clock = '00:00',
    this.hint = '',
    this.semanticLabel,
  });

  final OrbState state;
  final VoidCallback? onTap;
  final String clock;
  final String hint;
  final String? semanticLabel;

  @override
  State<ActionOrb> createState() => _ActionOrbState();
}

class _ActionOrbState extends State<ActionOrb> with TickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: Motion.orbSpin)
    ..repeat();
  late final _breathe = AnimationController(
    vsync: this,
    duration: Motion.orbBreathe,
  )..repeat(reverse: true);
  late final _scale = Tween(
    begin: Motion.orbBreatheMin,
    end: Motion.orbBreatheMax,
  ).animate(CurvedAnimation(parent: _breathe, curve: Curves.easeInOut));

  @override
  void dispose() {
    _spin.dispose();
    _breathe.dispose();
    super.dispose();
  }

  Gradient get _gradient => switch (widget.state) {
    OrbState.live => Brushes.disc,
    OrbState.paused => Brushes.paused,
    OrbState.idle || OrbState.speaking => Brushes.primary,
  };

  Color get _glow => switch (widget.state) {
    OrbState.live => Palette.red,
    OrbState.paused => Accent.amber,
    OrbState.idle || OrbState.speaking => Palette.greenDeep,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      // Each moving part is its own layer: the glow and the ring are drawn
      // once and only moved by the GPU, and the orb's blurred shadow is not
      // redrawn every frame.
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: 210,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ScaleTransition(
                scale: _scale,
                child: RepaintBoundary(
                  // The 35% glow strength is in the colours, not an Opacity
                  // layer, which would cost an offscreen pass every frame.
                  child: AnimatedContainer(
                    duration: Motion.fade,
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _glow.withValues(alpha: 0.7 * 0.35),
                          _glow.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              RotationTransition(
                turns: _spin,
                child: const RepaintBoundary(
                  child: SizedBox.square(
                    dimension: 184,
                    child: CustomPaint(painter: _SweepRingPainter()),
                  ),
                ),
              ),
              GestureDetector(
                onTap: widget.onTap,
                child: AnimatedContainer(
                  duration: Motion.fade,
                  width: Sizes.actionOrb,
                  height: Sizes.actionOrb,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _gradient,
                    border: Border.all(
                      color: Palette.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _glow.withValues(alpha: 0.45),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: RepaintBoundary(
                    child: AnimatedSwitcher(
                      duration: Motion.fade,
                      child: widget.state == OrbState.idle
                          ? ScaleTransition(
                              key: const ValueKey('idle'),
                              scale: _scale,
                              child: Container(
                                width: 62,
                                height: 62,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Palette.white,
                                    width: 5,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: const BoxDecoration(
                                    color: Palette.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            )
                          : MediaQuery.withNoTextScaling(
                              key: const ValueKey('clock'),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.clock,
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontFamily: Fonts.display,
                                      fontFamilyFallback: Fonts.fallback,
                                      fontSize: 32,
                                      height: 1.2,
                                      color: Palette.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  if (widget.hint.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 4,
                                        left: 10,
                                        right: 10,
                                      ),
                                      // A dark pill keeps the hint readable on
                                      // every colour the orb passes through.
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Palette.black.withValues(
                                            alpha: 0.28,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 3,
                                          ),
                                          // Shrinks a long hint to fit
                                          // rather than cutting it off.
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              widget.hint,
                                              maxLines: 1,
                                              style: const TextStyle(
                                                fontFamily: Fonts.body,
                                                fontFamilyFallback:
                                                    Fonts.fallback,
                                                fontSize: 12.5,
                                                height: 1.45,
                                                fontWeight: FontWeight.w600,
                                                fontVariations: [
                                                  FontVariation.weight(600),
                                                ],
                                                color: Palette.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SweepRingPainter extends CustomPainter {
  const _SweepRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..shader = Brushes.sweep.createShader(rect);
    canvas.drawCircle(rect.center, size.width / 2 - 3, paint);
  }

  @override
  bool shouldRepaint(_SweepRingPainter oldDelegate) => false;
}

/// Live waveform bars. [level] (0..1) drives them while listening; when
/// [synthetic] is true they move on their own (the AI is speaking).
class Waveform extends StatefulWidget {
  const Waveform({
    super.key,
    required this.level,
    required this.color,
    this.synthetic = false,
    this.bars = 24,
    this.height = 44,
  });

  final double level;
  final Color color;
  final bool synthetic;
  final int bars;
  final double height;

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();
  double _smooth = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final target = widget.synthetic ? 0.65 : widget.level;
            _smooth += (target - _smooth) * 0.18;
            return CustomPaint(
              size: Size(widget.bars * 7.0, widget.height),
              painter: _WavePainter(
                t: _c.value * 10,
                level: _smooth,
                color: widget.color,
                bars: widget.bars,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.t,
    required this.level,
    required this.color,
    required this.bars,
  });

  final double t;
  final double level;
  final Color color;
  final int bars;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / bars;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.min(4, w * 0.55);
    for (var i = 0; i < bars; i++) {
      final centre = 1 - ((i - bars / 2).abs() / (bars / 2)) * 0.6;
      final wobble =
          (math.sin(t * 7 + i * 0.9) +
              math.sin(t * 11.3 + i * 0.37) * 0.6 +
              2) /
          3.6;
      final amp = 0.12 + level * centre * (0.35 + 0.65 * wobble);
      final h = (size.height * amp.clamp(0.08, 1.0)).toDouble();
      final x = w * i + w / 2;
      canvas.drawLine(
        Offset(x, size.height / 2 - h / 2),
        Offset(x, size.height / 2 + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}
