import 'package:flutter/widgets.dart';
import 'package:path_parsing/path_parsing.dart';

part 'hero_icons_data.dart';

/// One Heroicons v2 glyph: its SVG path data on the 24px grid.
class HeroIconData {
  const HeroIconData(this.paths, {this.solid = false, this.custom});
  final List<String> paths;

  /// Solid icons are filled (even-odd); outline icons are stroked at 1.5px
  /// with round caps and joins.
  final bool solid;

  /// Custom drawn icons in the Heroicons style (e.g. the waveform).
  final void Function(Canvas canvas, Paint stroke)? custom;
}

/// Custom icons the design kit draws in the Heroicons style.
abstract final class HeroCustom {
  /// Audio waveform: five rounded bars, outline style.
  static const waveform = HeroIconData([
    'M4.5 10.5v3M8.25 7.5v9M12 4.5v15M15.75 7.5v9M19.5 10.5v3',
  ]);

  /// Plain record dot (solid).
  static const recordDot = HeroIconData([
    'M12 6.75a5.25 5.25 0 1 0 0 10.5 5.25 5.25 0 0 0 0-10.5Z',
  ], solid: true);
}

final _cache = <String, Path>{};

Path _parse(String d) => _cache.putIfAbsent(d, () {
  final proxy = _PathProxy();
  writeSvgPathDataToPath(d, proxy);
  return proxy.path;
});

class _PathProxy extends PathProxy {
  final path = Path();
  @override
  void close() => path.close();
  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);
  @override
  void lineTo(double x, double y) => path.lineTo(x, y);
  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
}

/// Draws a Heroicon tinted like a Material [Icon]: colour and size come from
/// the arguments, else from the surrounding [IconTheme].
class HeroIcon extends StatelessWidget {
  const HeroIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final HeroIconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    var c = color ?? theme.color ?? const Color(0xFF000000);
    final opacity = theme.opacity;
    if (color == null && opacity != null && opacity < 1) {
      c = c.withValues(alpha: c.a * opacity);
    }
    final glyph = SizedBox.square(
      dimension: s,
      child: CustomPaint(painter: _HeroPainter(icon, c)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: glyph);
    return Semantics(label: semanticLabel, child: glyph);
  }
}

class _HeroPainter extends CustomPainter {
  _HeroPainter(this.icon, this.color);
  final HeroIconData icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (icon.solid) {
      paint.style = PaintingStyle.fill;
    } else {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
    }
    for (final d in icon.paths) {
      final p = _parse(d);
      if (icon.solid) p.fillType = PathFillType.evenOdd;
      canvas.drawPath(p, paint);
    }
    icon.custom?.call(canvas, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeroPainter old) =>
      old.icon != icon || old.color != color;
}
