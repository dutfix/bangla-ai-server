import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';

// Section 6 components, rebuilt in Flutter with the same specs.

double fontScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) / 10;

/// Press feedback: shrink to 96% with a spring (damping 0.55, stiffness 600).
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController.unbounded(vsync: this, value: 1);
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: Motion.pressStiffness,
    ratio: Motion.pressDamping,
  );

  void _to(double target) {
    // A press can end after this widget has gone (a chat scrolled away or
    // a screen closed while the finger was still down).
    if (!mounted) return;
    _c.animateWith(SpringSimulation(_spring, _c.value, target, _c.velocity));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.enabled ? (_) => _to(Motion.pressScale) : null,
      onPointerUp: (_) => _to(1),
      onPointerCancel: (_) => _to(1),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.scale(scale: _c.value, child: child),
        child: widget.child,
      ),
    );
  }
}

/// Solid main action: Ink (light) / Sky (dark), 52dp, 12dp corners.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final HeroIconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            HeroIcon(icon!, size: Sizes.iconButton),
            const SizedBox(width: Space.sm),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
    return Pressable(
      enabled: onPressed != null,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// Secondary action: transparent, 1dp border, 48dp, 12dp corners.
class OutlineButton extends StatelessWidget {
  const OutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final HeroIconData? icon;
  final bool expand;

  /// Only for destructive actions (red).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed,
      style: color == null
          ? null
          : OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color!),
            ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            HeroIcon(icon!, size: Sizes.iconOutlineButton),
            const SizedBox(width: Space.sm),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
    return Pressable(
      enabled: onPressed != null,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// Pill chip, 40dp; selected = Ink (light) / Sky (dark).
class ChipButton extends StatelessWidget {
  const ChipButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.iconColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final HeroIconData? icon;
  final bool selected;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final app = AppColors.of(context);
    final enabled = onPressed != null;
    final bg = selected ? app.chipSelectedBg : s.surfaceContainerHigh;
    var fg = selected ? app.chipSelectedText : s.onSurface;
    if (!enabled) fg = fg.withValues(alpha: 0.5);
    return Pressable(
      enabled: enabled,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: bg),
        duration: Motion.fade,
        builder: (context, color, child) => Material(
          color: color,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.chipMinHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    HeroIcon(
                      icon!,
                      size: Sizes.iconChip,
                      color: selected ? fg : (iconColor ?? fg),
                    ),
                    const SizedBox(width: Space.s),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of chips: 8dp gaps, 16dp side padding.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: Space.rowGap),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Card: 16dp side margin built in, 20dp corners, surfaceContainer, 1dp
/// outlineVariant border, no shadow, no inner padding.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: Space.gutter),
    this.borderColor,
    this.borderWidth = 1,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: margin,
      child: Material(
        color: s.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(
            color: borderColor ?? s.outlineVariant,
            width: borderWidth,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// 40dp square, 12dp corners, accent at 13% behind a 22dp accent icon.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.accent,
    this.size = Sizes.iconBadge,
    this.iconSize = Sizes.iconBadgeGlyph,
    this.radius = Radii.button,
  });

  final HeroIconData icon;
  final Color accent;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: Alphas.iconBadge),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: HeroIcon(icon, size: iconSize, color: accent),
    );
  }
}

/// Settings row with the narrow-screen rules from the design file.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    this.sub,
    this.value,
    this.onTap,
    this.enabled = true,
    this.trailing,
    this.showChevron = true,
    this.titleColor,
  });

  final HeroIconData icon;
  final Color accent;
  final String title;
  final String? sub;
  final String? value;
  final VoidCallback? onTap;
  final bool enabled;
  final Widget? trailing;
  final bool showChevron;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final scale = fontScale(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final v = value;
          final under =
              v != null &&
              (w < Layout.settingValueUnderTitleBelow * scale || v.length > 18);
          final hideBadge = w < Layout.settingHideBadgeBelow * scale;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                if (!hideBadge) ...[
                  IconBadge(icon: icon, accent: accent),
                  const SizedBox(width: Space.l),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.titleMedium?.copyWith(
                          color: enabled
                              ? (titleColor ?? s.onSurface)
                              : s.onSurfaceVariant,
                        ),
                      ),
                      if (sub != null)
                        Text(
                          sub!,
                          style: t.bodyMedium?.copyWith(
                            color: s.onSurfaceVariant,
                          ),
                        ),
                      if (under)
                        Text(
                          v,
                          style: t.bodyMedium?.copyWith(color: s.primary),
                        ),
                    ],
                  ),
                ),
                if (v != null && !under) ...[
                  const SizedBox(width: Space.sm),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: w * 0.4),
                    child: Text(
                      v,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                    ),
                  ),
                ],
                ?trailing,
                if (trailing == null && showChevron && onTap != null) ...[
                  const SizedBox(width: Space.xs),
                  HeroIcon(
                    HeroIcons.chevronRight,
                    size: 20,
                    color: s.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Same layout with 11dp vertical padding and a Switch; the whole row toggles.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.value,
    required this.onChanged,
    this.sub,
  });

  final HeroIconData icon;
  final Color accent;
  final String title;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            IconBadge(icon: icon, accent: accent),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleMedium),
                  if (sub != null)
                    Text(
                      sub!,
                      style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Uppercase 12sp DM Sans Medium, 1.2 letter spacing, primary; 20dp start,
/// 22dp top, 8dp bottom.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.top = 22});
  final String text;
  final Widget? trailing;
  final double top;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.textInset,
        top,
        trailing == null ? Space.textInset : Space.sm,
        Space.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: fitted(
                context,
                AppText.sectionTitle,
              ).copyWith(color: s.primary),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The 8dp sky-gradient dot after every page title.
class TitleDot extends StatelessWidget {
  const TitleDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: Sizes.titleDot,
      height: Sizes.titleDot,
      decoration: const BoxDecoration(
        gradient: Brushes.primary,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Page title: Anton 21sp UPPERCASE + sky dot, optional sub line, back arrow,
/// leading item and trailing actions. Sits under the status bar.
class PageTitle extends StatelessWidget {
  const PageTitle({
    super.key,
    required this.title,
    this.sub,
    this.subWidget,
    this.onBack,
    this.leading,
    this.actions = const [],
    this.maxLines = 2,
  });

  final String title;
  final String? sub;
  final Widget? subWidget;
  final VoidCallback? onBack;
  final Widget? leading;
  final List<Widget> actions;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final hasStart = onBack != null || leading != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        hasStart ? 4 : Space.textInset,
        12,
        actions.isEmpty ? Space.textInset : Space.sm,
        4,
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: context.l10n.back,
              onPressed: onBack,
              icon: const HeroIcon(HeroIcons.arrowLeft),
            ),
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: title.toUpperCase()),
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: EdgeInsets.only(left: 6, top: 3),
                          child: TitleDot(),
                        ),
                      ),
                    ],
                  ),
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: t.headlineLarge?.copyWith(color: s.onSurface),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                  ),
                ?subWidget,
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Fixed title, scrolling content below, a 1dp divider once scrolled, and
/// content centred with a max width.
class PinnedPage extends StatefulWidget {
  const PinnedPage({
    super.key,
    required this.title,
    required this.children,
    this.sub,
    this.onBack,
    this.actions = const [],
    this.maxWidth = Layout.maxWidthPage,
    this.header,
  });

  final String title;
  final String? sub;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final List<Widget> children;
  final double maxWidth;

  /// Non-scrolling content under the title (e.g. a search field).
  final Widget? header;

  @override
  State<PinnedPage> createState() => _PinnedPageState();
}

class _PinnedPageState extends State<PinnedPage> {
  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: Column(
                children: [
                  PageTitle(
                    title: widget.title,
                    sub: widget.sub,
                    onBack: widget.onBack,
                    actions: widget.actions,
                  ),
                  ?widget.header,
                ],
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _scrolled ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: Divider(color: s.outlineVariant),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.depth == 0) {
                  final sc = n.metrics.pixels > 0;
                  if (sc != _scrolled) setState(() => _scrolled = sc);
                }
                return false;
              },
              child: ListView(
                padding: EdgeInsets.only(
                  bottom:
                      Space.pageBottom + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  // Each row takes the page's full width, so short text
                  // and chip rows start at the left edge like the rest
                  // instead of floating in the middle.
                  for (final c in widget.children)
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: widget.maxWidth),
                        child: SizedBox(width: double.infinity, child: c),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 44dp icon, title and sub, centred; 32dp / 56dp padding.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.sub,
    this.action,
  });

  final HeroIconData icon;
  final String title;
  final String? sub;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.emptyH,
        vertical: Space.emptyV,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HeroIcon(icon, size: Sizes.iconEmpty, color: s.onSurfaceVariant),
          const SizedBox(height: Space.ml),
          Text(title, textAlign: TextAlign.center, style: t.titleMedium),
          if (sub != null)
            Text(
              sub!,
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
            ),
          if (action != null) ...[
            const SizedBox(height: Space.gutter),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Single-line search field: 12dp corners, magnifying glass, clear button.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: Space.gutter),
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.button),
      borderSide: BorderSide(color: s.outline),
    );
    return Padding(
      padding: widget.padding,
      child: TextField(
        controller: _c,
        maxLines: 1,
        textInputAction: TextInputAction.search,
        onChanged: (v) {
          setState(() {});
          widget.onChanged(v);
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          hintMaxLines: 1,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: s.primary, width: 2),
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: HeroIcon(
              HeroIcons.magnifyingGlass,
              size: Sizes.iconButton,
              color: s.onSurfaceVariant,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 44),
          suffixIcon: _c.text.isEmpty
              ? null
              : IconButton(
                  tooltip: context.l10n.clear,
                  onPressed: () {
                    _c.clear();
                    setState(() {});
                    widget.onChanged('');
                  },
                  icon: HeroIcon(
                    HeroIcons.xCircle,
                    size: Sizes.iconButton,
                    color: s.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 56dp (68dp big) circle with accent 16% fill and 35% border, label below.
class CircleAction extends StatelessWidget {
  const CircleAction({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.big = false,
  });

  final HeroIconData icon;
  final String label;
  final Color accent;
  final VoidCallback? onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final size = big ? Sizes.circleActionBig : Sizes.circleAction;
    final enabled = onTap != null;
    // The label is part of the button: a tap on it counts too, and screen
    // readers hear one button with the label.
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Pressable(
                enabled: enabled,
                child: Material(
                  color: accent.withValues(alpha: Alphas.circleActionFill),
                  shape: CircleBorder(
                    side: BorderSide(
                      color: accent.withValues(
                        alpha: Alphas.circleActionBorder,
                      ),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTap,
                    child: SizedBox.square(
                      dimension: size,
                      child: Center(
                        child: HeroIcon(
                          icon,
                          size: big ? Sizes.iconBig : Sizes.iconThumb,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.s),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.labelLarge?.copyWith(color: s.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hero action card: flag-green gradient, 24dp corners, white text, and a
/// round flag-red disc with the icon (the flag's red sun on green).
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.title,
    required this.sub,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String sub;
  final HeroIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.m,
      ),
      child: Pressable(
        child: Material(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.hero),
          ),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: const BoxDecoration(gradient: Brushes.primary),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: t.titleLarge?.copyWith(color: Palette.white),
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            sub,
                            style: t.bodyMedium?.copyWith(
                              color: Palette.white.withValues(alpha: 0.95),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.l),
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Palette.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Palette.black.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: HeroIcon(
                          icon,
                          size: Sizes.iconBig,
                          color: Palette.white,
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
    );
  }
}

/// Fully round, black 55%, white 11sp SemiBold.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.textColor});
  final String text;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color ?? Palette.black.withValues(alpha: Alphas.pillBlack),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        text,
        style: fitted(
          context,
          AppText.pill,
        ).copyWith(color: textColor ?? Palette.white),
      ),
    );
  }
}

/// One option in a [showChoiceSheet].
class ChoiceOption<T> {
  const ChoiceOption(this.value, this.label, {this.sub, this.enabled = true});
  final T value;
  final String label;
  final String? sub;
  final bool enabled;
}

/// Choice list bottom sheet: titleLarge title, 16dp-corner options, the
/// selected one with a primary 12% fill and a check.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<ChoiceOption<T>> options,
  T? selected,
  Widget? footer,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final s = Theme.of(context).colorScheme;
      final t = Theme.of(context).textTheme;
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(title, style: t.titleLarge),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final o in options)
                      _ChoiceTile(
                        option: o,
                        selected: o.value == selected,
                        scheme: s,
                        text: t,
                      ),
                  ],
                ),
              ),
              ?footer,
            ],
          ),
        ),
      );
    },
  );
}

class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.option,
    required this.selected,
    required this.scheme,
    required this.text,
  });

  final ChoiceOption<T> option;
  final bool selected;
  final ColorScheme scheme;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final s = scheme;
    final disabled = !option.enabled;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected
            ? s.primary.withValues(alpha: Alphas.selectedRow)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.tile),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : () => Navigator.pop(context, option.value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        style: text.titleMedium?.copyWith(
                          color: disabled
                              ? s.onSurfaceVariant.withValues(alpha: 0.5)
                              : selected
                              ? s.primary
                              : s.onSurface,
                        ),
                      ),
                      if (option.sub != null)
                        Text(
                          option.sub!,
                          style: text.bodyMedium?.copyWith(
                            color: s.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (selected) HeroIcon(HeroIcons.check, color: s.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Material 3 dialog; a destructive confirm uses the error colour.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) {
      final s = Theme.of(c).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(c.l10n.cancel),
          ),
          TextButton(
            style: destructive
                ? TextButton.styleFrom(foregroundColor: s.error)
                : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirm),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}

/// A dialog with one text field (rename and the like).
Future<String?> showTextDialog(
  BuildContext context, {
  required String title,
  required String initial,
  required String confirm,
  String? hint,
  int maxLength = 80,
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: maxLength,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          child: Text(confirm),
        ),
      ],
    ),
  ).whenComplete(
    () => Future<void>.delayed(const Duration(milliseconds: 400), c.dispose),
  );
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// A small round icon button used for message actions (copy, speak...).
class SmallIconAction extends StatelessWidget {
  const SmallIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final HeroIconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: HeroIcon(icon, size: 19, color: color ?? s.onSurfaceVariant),
    );
  }
}
