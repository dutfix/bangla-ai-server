import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../services/account_store.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';

/// The user's round picture, or their first letter on green.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.account, this.size = 40});

  final Account? account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: Brushes.primary,
      ),
      child: a == null
          ? HeroIcon(HeroIcons.user, size: size * 0.52, color: Palette.white)
          : Text(
              a.initial,
              style: TextStyle(
                color: Palette.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.42,
                height: 1,
              ),
            ),
    );
    final url = a?.avatar;
    if (url == null) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
        frameBuilder: (_, child, frame, sync) => sync || frame != null
            ? child
            : Stack(
                children: [
                  fallback,
                  Positioned.fill(child: Opacity(opacity: 0, child: child)),
                ],
              ),
      ),
    );
  }
}

/// A text field for the sign-in pages: label above, icon, error under it.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.focusNode,
    this.hint,
    this.password = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.onSubmitted,
    this.error,
    this.enabled = true,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? hint;
  final HeroIconData icon;
  final bool password;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final String? error;
  final bool enabled;
  final int? maxLength;
  final TextCapitalization textCapitalization;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        obscureText: widget.password && _hidden,
        enableSuggestions: !widget.password,
        autocorrect: false,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        autofillHints: widget.autofillHints,
        onSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        maxLength: widget.maxLength,
        textCapitalization: widget.textCapitalization,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: widget.error,
          errorMaxLines: 3,
          counterText: '',
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.ml),
            child: HeroIcon(
              widget.icon,
              size: Sizes.iconButton,
              color: s.onSurfaceVariant,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 44,
          ),
          suffixIcon: widget.password
              ? IconButton(
                  tooltip: _hidden ? t.showPassword : t.hidePassword,
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: HeroIcon(
                    _hidden ? HeroIcons.eye : HeroIcons.eyeSlash,
                    size: Sizes.iconButton,
                    color: s.onSurfaceVariant,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// The white "Continue with Google" button with Google's G.
class GoogleButton extends StatelessWidget {
  const GoogleButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.busy = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      height: Sizes.buttonPrimaryMinHeight,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: dark ? Accent.darkCard2 : Palette.white,
          foregroundColor: s.onSurface,
          side: BorderSide(color: s.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.button),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            else
              const SizedBox(
                width: 20,
                height: 20,
                child: CustomPaint(painter: _GoogleG()),
              ),
            const SizedBox(width: Space.ml),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

/// Google's four-colour G, drawn (no image file needed).
class _GoogleG extends CustomPainter {
  const _GoogleG();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final stroke = w * 0.2;
    final r = (w - stroke) / 2;
    final c = Offset(w / 2, w / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    Paint p(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const deg = 3.14159265 / 180;
    canvas.drawArc(
      rect,
      -40 * deg,
      -100 * deg,
      false,
      p(const Color(0xFFEA4335)),
    );
    canvas.drawArc(
      rect,
      -140 * deg,
      -80 * deg,
      false,
      p(const Color(0xFFFBBC05)),
    );
    canvas.drawArc(
      rect,
      -220 * deg,
      -95 * deg,
      false,
      p(const Color(0xFF34A853)),
    );
    canvas.drawArc(
      rect,
      -315 * deg,
      -45 * deg,
      false,
      p(const Color(0xFF4285F4)),
    );
    final bar = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(w / 2, w / 2 - stroke / 2, r + stroke / 2, stroke),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A filled button that shows a spinner while [busy].
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: Sizes.buttonPrimaryMinHeight,
      child: FilledButton(
        onPressed: busy ? () {} : onPressed,
        child: AnimatedSwitcher(
          duration: Motion.fade,
          child: busy
              ? SizedBox(
                  key: const ValueKey('busy'),
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: s.onPrimary,
                  ),
                )
              : Text(
                  label,
                  key: const ValueKey('label'),
                  textAlign: TextAlign.center,
                ),
        ),
      ),
    );
  }
}

/// A message box for errors and notes inside a form.
class FormNote extends StatelessWidget {
  const FormNote({super.key, required this.text, this.error = true});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final color = error ? s.error : Palette.success;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: Space.l),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.ml,
        vertical: Space.m,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.button),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeroIcon(
            error ? HeroIcons.exclamationTriangle : HeroIcons.checkCircle,
            size: 18,
            color: color,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: color, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// The user-facing words for an accounts error.
String accountErrorText(BuildContext context, Object e) {
  final t = context.l10n;
  if (e is! AccountException) return t.errGeneric;
  return switch (e.code) {
    'wrong_login' => t.errWrongLogin,
    'email_taken' => t.errEmailTaken,
    'use_google' => t.errUseGoogle,
    'invalid_email' => t.errEmail,
    'weak_password' => t.errPassword,
    'invalid_name' => t.errName,
    'network' => t.errNetwork,
    'timeout' => t.errTimeout,
    'accounts_unavailable' || 'unavailable' => t.errAccountsDown,
    'too_soon' => t.errTooSoon(localDigits('${e.retryAfter ?? 60}')),
    'wrong_code' =>
      e.triesLeft != null
          ? t.triesLeft(localDigits('${e.triesLeft}'))
          : t.errWrongCode,
    'invalid_code' => t.errCodeDigits,
    'too_many_tries' => t.errTooManyTries,
    'wrong_password' => t.errWrongCurrent,
    'invalid_image' || 'image_too_large' => t.errImage,
    'bad_ticket' || 'google_failed' => t.googleFailed,
    _ => e.serverMessage.isNotEmpty ? e.serverMessage : t.errGeneric,
  };
}

/// The words for a Google sign-in that came back with ?auth_error=.
String googleErrorText(BuildContext context, String code) {
  final t = context.l10n;
  return switch (code) {
    'cancelled' => t.googleCancelled,
    'google_off' => t.googleOff,
    'network' => t.errNetwork,
    'timeout' => t.errTimeout,
    _ => t.googleFailed,
  };
}

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
bool looksLikeEmail(String s) => _emailRe.hasMatch(s.trim());
