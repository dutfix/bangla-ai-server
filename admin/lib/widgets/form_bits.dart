import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import 'components.dart';

/// A labelled text field with the card's padding.
class Field extends StatelessWidget {
  const Field(
    this.controller,
    this.label, {
    super.key,
    this.hint,
    this.helper,
    this.maxLines = 1,
    this.obscure = false,
    this.suffix,
    this.type,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final int maxLines;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? type;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: TextField(
      controller: controller,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      minLines: 1,
      keyboardType: type,
      autocorrect: false,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 4,
        suffixIcon: suffix,
        alignLabelWithHint: maxLines > 1,
      ),
    ),
  );
}

/// Grey explanatory text under a section title.
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        text,
        style: t.bodyMedium?.copyWith(color: color ?? sc.onSurfaceVariant),
      ),
    );
  }
}

/// A titled slider with its value at the end.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
    this.sub,
  });

  final String title;
  final String? sub;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: t.titleSmall)),
              Text(
                format(value),
                style: t.titleSmall?.copyWith(color: sc.primary),
              ),
            ],
          ),
          if (sub != null)
            Text(
              sub!,
              style: t.bodySmall?.copyWith(color: sc.onSurfaceVariant),
            ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: format(value),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// A number tile on the overview: big value, label, optional sub line.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.sub,
  });

  final String label;
  final String value;
  final String? sub;
  final HeroIconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    return Material(
      color: sc.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.tile),
        side: BorderSide(color: sc.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: icon,
                  accent: accent,
                  size: 30,
                  iconSize: 17,
                  radius: 9,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelLarge?.copyWith(color: sc.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (sub != null)
              Text(
                sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(color: sc.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tiles in a grid: 2 across on a phone, more on wider screens.
class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth - 32;
        final cols = w >= 640
            ? 4
            : w >= 420
            ? 3
            : 2;
        const gap = 10.0;
        final tile = (w - gap * (cols - 1)) / cols;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final c in children) SizedBox(width: tile, child: c),
            ],
          ),
        );
      },
    );
  }
}

/// One bar series of a [BarChart].
class BarSeries {
  const BarSeries(this.label, this.color, this.values);
  final String label;
  final Color color;
  final List<num> values;
}

/// Stacked daily bars with a legend and first/last day labels.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.series,
    required this.labels,
    this.height = 150,
  });

  final List<BarSeries> series;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    final n = labels.length;
    num top = 0;
    for (var i = 0; i < n; i++) {
      num sum = 0;
      for (final s in series) {
        sum += i < s.values.length ? s.values[i] : 0;
      }
      top = math.max(top, sum);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final s in series)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(s.label, style: t.bodySmall),
                  ],
                ),
              Text(
                'Top: $top',
                style: t.bodySmall?.copyWith(color: sc.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: height,
            child: Semantics(
              label:
                  '${series.map((s) => '${s.label}: ${s.values.fold<num>(0, (a, b) => a + b)}').join(', ')} over $n days',
              child: CustomPaint(
                size: Size.infinite,
                painter: _BarPainter(
                  series,
                  n,
                  top.toDouble(),
                  sc.outlineVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (n > 0)
            Row(
              children: [
                Text(
                  labels.first,
                  style: t.bodySmall?.copyWith(color: sc.onSurfaceVariant),
                ),
                const Spacer(),
                Text(
                  labels.last,
                  style: t.bodySmall?.copyWith(color: sc.onSurfaceVariant),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.series, this.n, this.top, this.grid);
  final List<BarSeries> series;
  final int n;
  final double top;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    if (n == 0 || top <= 0) return;
    final slot = size.width / n;
    final w = math.max(2.0, slot * 0.68);
    for (var i = 0; i < n; i++) {
      var y = size.height;
      for (final s in series) {
        final v = (i < s.values.length ? s.values[i] : 0).toDouble();
        if (v <= 0) continue;
        final h = size.height * v / top;
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(i * slot + (slot - w) / 2, y - h, w, h),
          Radius.circular(math.min(3, w / 2)),
        );
        canvas.drawRRect(r, Paint()..color = s.color);
        y -= h;
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.series != series || old.top != top || old.n != n;
}

/// Horizontal share bars: name, count, a bar of its share.
class ShareList extends StatelessWidget {
  const ShareList({
    super.key,
    required this.items,
    required this.color,
    this.empty = 'Nothing yet.',
  });
  final Map<String, num> items;
  final Color color;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    final list = items.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = list.fold<num>(0, (a, e) => a + e.value);
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          empty,
          style: t.bodyMedium?.copyWith(color: sc.onSurfaceVariant),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          for (final e in list.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium,
                        ),
                      ),
                      Text(
                        '${e.value} · ${(e.value * 100 / total).round()}%',
                        style: t.bodySmall?.copyWith(
                          color: sc.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : e.value / total,
                      minHeight: 6,
                      color: color,
                      backgroundColor: sc.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The bar that slides up when there are unsaved changes.
class SaveBar extends StatelessWidget {
  const SaveBar({
    super.key,
    required this.saving,
    required this.onSave,
    required this.onDiscard,
  });
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    return Material(
      color: sc.surfaceContainerHighest,
      elevation: 3,
      borderRadius: BorderRadius.circular(Radii.tile),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(child: Text('Unsaved changes', style: t.titleSmall)),
            TextButton(
              onPressed: saving ? null : onDiscard,
              child: const Text('Undo'),
            ),
            const SizedBox(width: 4),
            PrimaryButton(
              label: saving ? 'Saving...' : 'Save for all users',
              icon: HeroIcons.check,
              onPressed: saving ? null : onSave,
            ),
          ],
        ),
      ),
    );
  }
}
