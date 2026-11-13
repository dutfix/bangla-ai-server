import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import 'components.dart';

/// The message box: a text field and one round button on the right that
/// sends, stops the reply, or starts a voice call when the box is empty.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.generating,
    required this.onSend,
    required this.onStop,
    this.onVoiceCall,
    this.maxLines = 6,
    this.focusNode,
  });

  final TextEditingController controller;
  final bool generating;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  /// Null when the admin has voice off: the button is a send button.
  final VoidCallback? onVoiceCall;

  /// How tall the box may grow before it scrolls.
  final int maxLines;
  final FocusNode? focusNode;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  TextEditingController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void didUpdateWidget(Composer old) {
    super.didUpdateWidget(old);
    if (old.controller != c) {
      old.controller.removeListener(_changed);
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  void _send() {
    final text = c.text.trim();
    if (text.isEmpty) return;
    c.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final hasText = c.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: s.surfaceContainer,
        borderRadius: BorderRadius.circular(Radii.hero),
        border: Border.all(color: s.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: c,
              focusNode: widget.focusNode,
              minLines: 1,
              maxLines: widget.maxLines,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              style: t.bodyLarge,
              decoration: InputDecoration(
                hintText: context.l10n.messageHint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
              ),
            ),
          ),
          _ActionButton(
            mode: widget.generating
                ? _Mode.stop
                : hasText || widget.onVoiceCall == null
                ? _Mode.send
                : _Mode.voice,
            enabled: widget.generating || hasText || widget.onVoiceCall != null,
            onSend: _send,
            onStop: widget.onStop,
            onVoice: widget.onVoiceCall ?? () {},
          ),
        ],
      ),
    );
  }
}

enum _Mode { send, stop, voice }

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.mode,
    required this.onSend,
    required this.onStop,
    required this.onVoice,
    this.enabled = true,
  });

  final _Mode mode;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, tip, tap, gradient) = switch (mode) {
      _Mode.send => (HeroIcons.arrowUp, l10n.send, onSend, false),
      _Mode.stop => (HeroIcons.stopSolid, l10n.stopGenerating, onStop, false),
      _Mode.voice => (HeroCustom.waveform, l10n.startVoiceCall, onVoice, true),
    };
    final dark = Theme.of(context).brightness == Brightness.dark;
    final solid = dark ? Palette.greenBright : Palette.green;
    final onSolid = dark ? Accent.onGreenDark : Palette.white;
    return Tooltip(
      message: tip,
      child: Pressable(
        child: Semantics(
          button: true,
          label: tip,
          child: GestureDetector(
            onTap: enabled ? tap : null,
            child: AnimatedOpacity(
              duration: Motion.fade,
              opacity: enabled ? 1 : 0.45,
              child: AnimatedContainer(
                duration: Motion.fade,
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: gradient ? null : solid,
                  gradient: gradient ? Brushes.primary : null,
                ),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration: Motion.fade,
                  child: HeroIcon(
                    icon,
                    key: ValueKey(mode),
                    size: mode == _Mode.stop ? 18 : 22,
                    color: gradient ? Palette.white : onSolid,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
