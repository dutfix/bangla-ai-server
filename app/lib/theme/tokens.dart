// FLARECAP design tokens, recoloured for Bangla AI in the Bangladesh flag's
// green and red. Layout, type scale and motion are unchanged from FLARECAP.
// Every colour, size, radius and timing in the app comes from here or from
// the Material 3 colour schemes in app_theme.dart. Tints are only made by
// lowering the alpha of a token, with the alphas listed in [Alphas].

import 'package:flutter/widgets.dart';

/// 2.1 Base palette: the Bangladesh flag. Green and red were sampled from
/// the flag picture the user supplied (green #006A4E, red #F42A40, which is
/// the flag's official #F42A41 within one step).
abstract final class Palette {
  /// Flag green: the main brand colour (primary).
  static const green = Color(0xFF006A4E);

  /// Darker green for gradient ends and pressed states.
  static const greenDeep = Color(0xFF004D38);

  /// Brighter green: the primary colour in dark mode and gradient starts.
  static const greenBright = Color(0xFF2DBE8A);
  static const greenLight = Color(0xFFA9DCC8);
  static const greenExtraLight = Color(0xFFE5F3ED);

  /// Flag red: the accent (the red disc).
  static const red = Color(0xFFF42A41);
  static const redLight = Color(0xFFFF6B7B);

  /// Text ink: a green-tinted near black.
  static const ink = Color(0xFF13241D);
  static const active = Color(0xFF1E1E1E);
  static const success = Color(0xFF0E9F6E);
  static const warning = Color(0xFFB25E09);
  static const error = Color(0xFFC62828);
  static const bg = Color(0xFFFFFFFF);
  static const bg2 = Color(0xFFF6F9F7);
  static const bg3 = Color(0xFFE7EEEA);
  static const chip = Color(0xFFF0F5F2);
  static const stroke = Color(0xFFDDE7E2);
  static const text2 = Color(0xFF4D5B55);
  static const link = Color(0xFF00805C);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
}

/// 2.2 Accents (icon badges, states).
abstract final class Accent {
  /// Flag green badge.
  static const green = Color(0xFF00875F);

  /// Flag red badge.
  static const flagRed = Color(0xFFF42A41);

  /// Errors, hang-up and recording.
  static const red = Color(0xFFD32F2F);
  static const teal = Color(0xFF0E9F8E);
  static const amber = Color(0xFFF29A2E);
  static const darkBg = Color(0xFF07130E);
  static const darkCard = Color(0xFF0F1F18);
  static const darkCard2 = Color(0xFF172B22);

  /// Text on the bright green used in dark mode.
  static const onGreenDark = Color(0xFF00170F);

  /// Start colour of Brushes.record.
  static const recordStart = Color(0xFFFF5A6A);

  /// The floating bubble menu: Ink at 94%.
  static const bubbleMenu = Color(0xF013241D);
}

/// 2.2 Tint alphas.
abstract final class Alphas {
  static const selectedRow = 0.12;
  static const iconBox = 0.12;
  static const iconBadge = 0.13;
  static const navIndicator = 0.14;
  static const circleActionFill = 0.16;
  static const circleActionBorder = 0.35;
  static const quickTileBorder = 0.6;
  static const heroSubText = 0.8;
  static const pillBlack = 0.55;
}

/// 2.3 Gradients.
abstract final class Brushes {
  static const primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00805C), Palette.green],
  );

  /// The voice orb's ring: green with a red flare, like the flag's disc.
  static const sweep = SweepGradient(
    colors: [
      Palette.greenBright,
      Palette.green,
      Palette.red,
      Palette.greenBright,
    ],
  );
  static final soft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Palette.green.withValues(alpha: 0.16),
      Palette.greenExtraLight.withValues(alpha: 0.10),
      Palette.red.withValues(alpha: 0.10),
    ],
  );

  /// The flag's red disc, used for the orb core while listening.
  static const disc = RadialGradient(colors: [Palette.redLight, Palette.red]);
  static const record = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Accent.recordStart, Palette.red],
  );
  static const paused = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Accent.amber, Palette.red],
  );
}

/// 5. Corner radii (dp).
abstract final class Radii {
  static const xs = 8.0; // text fields
  static const thumb = 10.0; // list-row thumbnails
  static const button = 12.0; // buttons, icon badges, search field
  static const tile = 16.0; // list rows, sheet options, quick-grid
  static const toolTile = 18.0;
  static const card = 20.0; // cards, quick tiles
  static const hero = 24.0; // hero cards, dialogs
  static const bubbleMenu = 28.0;
  static const pill = 9999.0;
}

/// 5. Spacing scale (dp).
abstract final class Space {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const s = 6.0;
  static const sm = 8.0;
  static const m = 10.0;
  static const ml = 12.0;
  static const l = 14.0;
  static const gutter = 16.0; // page gutter for cards, fields, buttons
  static const s18 = 18.0;
  static const textInset = 20.0; // page title and section titles
  static const xl = 22.0;
  static const xxl = 24.0;
  static const hero = 26.0;
  static const emptyH = 32.0;
  static const emptyV = 56.0;
  static const tileGap = 10.0;
  static const rowGap = 8.0;
  static const pageBottom = 24.0;
}

/// 11.1 Sizes (dp).
abstract final class Sizes {
  static const buttonPrimaryMinHeight = 52.0;
  static const buttonOutlineMinHeight = 48.0;
  static const chipMinHeight = 40.0;
  static const touchTarget = 48.0;
  static const iconBadge = 40.0;
  static const icon = 24.0;
  static const iconBadgeGlyph = 22.0;
  static const iconButton = 20.0; // in primary buttons and text fields
  static const iconOutlineButton = 19.0;
  static const iconChip = 17.0;
  static const iconThumb = 26.0;
  static const iconBig = 32.0;
  static const iconEmpty = 44.0;
  static const titleDot = 8.0;
  static const circleAction = 56.0;
  static const circleActionBig = 68.0;
  static const actionOrb = 150.0;
  static const bubble = 56.0;
  static const bubbleMenuButton = 44.0;
}

/// 7. Layout.
/// Chat page message layout (ChatGPT / Claude style).
abstract final class ChatLayout {
  /// Side padding of the message list.
  static const side = 18.0;

  /// Gap between two messages.
  static const gap = 20.0;

  /// A user bubble is at most this share of the column width.
  static const userBubbleMax = 0.8;

  /// Visual inset of the 19dp icon inside a compact icon button, used to
  /// line the action icons up with the message edge.
  static const actionInset = 10.0;
}

abstract final class Layout {
  static const railBreakpoint = 600.0;
  static const maxWidthPage = 760.0;
  static const maxWidthGrid = 900.0;
  static const settingValueUnderTitleBelow = 340.0;
  static const settingHideBadgeBelow = 300.0;

  /// Width of the chat history sidebar (drawer on phones, fixed at 600dp+).
  static const sidebarWidth = 300.0;
}

/// 8. Motion.
abstract final class Motion {
  static const pressScale = 0.96;
  static const pressDamping = 0.55;
  static const pressStiffness = 600.0;
  static const screenEnterScaleFrom = 0.96;
  static const orbSpin = Duration(milliseconds: 6000);
  static const orbBreathe = Duration(milliseconds: 1400);
  static const orbBreatheMin = 0.92;
  static const orbBreatheMax = 1.06;
  static const bubblePulse = Duration(milliseconds: 600);
  static const fade = Duration(milliseconds: 250);
}

/// Font families bundled in assets/fonts (all SIL OFL 1.1).
abstract final class Fonts {
  static const body = 'DM Sans';
  static const display = 'Anton';

  /// Bangla script. DM Sans, Anton and DM Mono have no Bengali glyphs, so
  /// every style falls back to this variable font (weight 100-900).
  static const bangla = 'Noto Sans Bengali';
  static const fallback = [bangla];

  /// Code blocks only. DM Mono is the DM type family's monospace cut.
  static const mono = 'DM Mono';
}
