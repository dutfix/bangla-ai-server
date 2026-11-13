import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../models/chat.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import 'components.dart';
import 'markdown_view.dart';

/// One chat message, laid out like ChatGPT / Claude: the user's message is a
/// right-aligned bubble (at most 80% wide), the AI's reply is open, full-width
/// Markdown with no bubble. The actions sit in a row under each message, their
/// icons lined up with the message's own edge.
class MessageTile extends StatefulWidget {
  const MessageTile({
    super.key,
    required this.message,
    required this.streaming,
    required this.isLastReply,
    required this.reading,
    required this.busy,
    required this.onRegenerate,
    required this.onEdit,
    this.onSpeak,
  });

  final ChatMessage message;

  /// This reply is streaming in right now.
  final bool streaming;

  /// The newest AI reply (only that one offers Regenerate).
  final bool isLastReply;

  /// Being read aloud now.
  final bool reading;

  /// A reply or a voice call is running, so edits wait.
  final bool busy;
  final VoidCallback onRegenerate;
  final ValueChanged<String> onEdit;

  /// Null when the admin has voice off: no read-aloud button.
  final VoidCallback? onSpeak;

  @override
  State<MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<MessageTile> {
  bool _editing = false;
  bool _copied = false;
  late final _edit = TextEditingController();

  ChatMessage get m => widget.message;

  @override
  void dispose() {
    _edit.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: m.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    // Every message has the same gap below it; the action row is part of the
    // message, so the gap is measured from the actions.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ChatLayout.side,
        0,
        ChatLayout.side,
        ChatLayout.gap,
      ),
      // Full width, so a user message sits on the right edge and a reply on
      // the left, however short either is. (The list centres each row in a
      // max-width column; without this a short message shrank to its own
      // width and ended up in the middle.)
      child: SizedBox(
        width: double.infinity,
        child: m.isUser ? _user(context) : _assistant(context),
      ),
    );
  }

  Widget _voiceTag(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HeroIcon(HeroCustom.waveform, size: 14, color: s.primary),
          const SizedBox(width: 4),
          Text(
            context.l10n.voiceCall,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: s.primary),
          ),
        ],
      ),
    );
  }

  Widget _user(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    if (_editing) return _editor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (m.viaVoice) _voiceTag(context),
        LayoutBuilder(
          builder: (context, box) => ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: box.maxWidth * ChatLayout.userBubbleMax,
            ),
            child: GestureDetector(
              onLongPress: _copy,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: s.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(Radii.card),
                    topRight: Radius.circular(Radii.card),
                    bottomLeft: Radius.circular(Radii.card),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: SelectableText(
                  m.text,
                  style: t.bodyLarge?.copyWith(color: s.onPrimaryContainer),
                ),
              ),
            ),
          ),
        ),
        _actionRow(
          end: true,
          children: [
            SmallIconAction(
              icon: _copied
                  ? HeroIcons.clipboardDocumentCheck
                  : HeroIcons.clipboardDocument,
              tooltip: _copied ? context.l10n.copied : context.l10n.copy,
              color: _copied ? Palette.success : null,
              onPressed: _copy,
            ),
            SmallIconAction(
              icon: HeroIcons.pencil,
              tooltip: context.l10n.editAndResend,
              onPressed: widget.busy
                  ? null
                  : () => setState(() {
                      _edit.text = m.text;
                      _editing = true;
                    }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _editor(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: s.surfaceContainer,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: s.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _edit,
            autofocus: true,
            minLines: 1,
            maxLines: 10,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.all(4),
              isDense: true,
            ),
          ),
          const SizedBox(height: Space.m),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              OutlineButton(
                label: context.l10n.cancel,
                onPressed: () => setState(() => _editing = false),
              ),
              PrimaryButton(
                label: context.l10n.send,
                icon: HeroIcons.arrowUp,
                onPressed: () {
                  final text = _edit.text.trim();
                  if (text.isEmpty) return;
                  setState(() => _editing = false);
                  widget.onEdit(text);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _assistant(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final waiting = widget.streaming && m.text.isEmpty;
    final done = !widget.streaming;
    // Full width, no bubble. A small mark heads the reply while it waits.
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.viaVoice) _voiceTag(context),
          if (waiting)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AssistantAvatar(size: 26),
                  SizedBox(width: Space.ml),
                  TypingDots(),
                ],
              ),
            )
          else if (m.text.isNotEmpty)
            MarkdownView(data: m.text, selectable: done, live: !done),
          if (m.error != null) ...[
            const SizedBox(height: Space.sm),
            _errorBox(context),
          ],
          if (done) ...[
            if (m.stopped)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  m.viaVoice ? context.l10n.interrupted : context.l10n.stopped,
                  style: t.labelMedium?.copyWith(color: s.onSurfaceVariant),
                ),
              ),
            _assistantActions(context),
          ],
        ],
      ),
    );
  }

  /// The action icons under a message. Compact icon buttons pad their icon,
  /// so the row is shifted by that inset to line the first (or, for the
  /// user, the last) icon up with the message's edge.
  Widget _actionRow({required bool end, required List<Widget> children}) {
    return Transform.translate(
      offset: Offset(end ? ChatLayout.actionInset : -ChatLayout.actionInset, 0),
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }

  Widget _assistantActions(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final hasText = m.text.trim().isNotEmpty;
    return _actionRow(
      end: false,
      children: [
        if (hasText) ...[
          SmallIconAction(
            icon: _copied
                ? HeroIcons.clipboardDocumentCheck
                : HeroIcons.clipboardDocument,
            tooltip: _copied ? context.l10n.copied : context.l10n.copy,
            color: _copied ? Palette.success : null,
            onPressed: _copy,
          ),
          if (widget.onSpeak != null)
            SmallIconAction(
              icon: widget.reading
                  ? HeroIcons.stopSolid
                  : HeroIcons.speakerWave,
              tooltip: widget.reading
                  ? context.l10n.stopReading
                  : context.l10n.readAloud,
              color: widget.reading ? s.primary : null,
              onPressed: widget.onSpeak,
            ),
        ],
        if (widget.isLastReply)
          SmallIconAction(
            icon: HeroIcons.arrowPath,
            tooltip: context.l10n.regenerate,
            onPressed: widget.busy ? null : widget.onRegenerate,
          ),
      ],
    );
  }

  Widget _errorBox(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.ml),
      decoration: BoxDecoration(
        color: s.error.withValues(alpha: Alphas.iconBox),
        borderRadius: BorderRadius.circular(Radii.tile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroIcon(HeroIcons.exclamationTriangle, size: 20, color: s.error),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  m.error!,
                  style: t.bodyMedium?.copyWith(color: s.onSurface),
                ),
              ),
            ],
          ),
          if (widget.isLastReply && !widget.busy) ...[
            const SizedBox(height: Space.m),
            OutlineButton(
              label: context.l10n.tryAgain,
              icon: HeroIcons.arrowPath,
              onPressed: widget.onRegenerate,
            ),
          ],
        ],
      ),
    );
  }
}

/// The AI's mark: the Bangla AI tiger logo in a circle.
class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({super.key, this.size = 30});
  final double size;

  static const asset = 'assets/branding/logo.png';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          // Draw at the size shown, not the full 1024px file.
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, _, _) => const DecoratedBox(
            decoration: BoxDecoration(
              color: Palette.green,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots that pulse while the AI is thinking.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: context.l10n.thinking,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Opacity(
                  opacity:
                      0.3 +
                      0.7 *
                          (1 - ((_c.value * 3 - i) % 3).clamp(0, 1).toDouble()),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
