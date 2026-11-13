import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../l10n/l10n.dart';
import '../services/call_controller.dart';
import '../theme/app_theme.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/voice_orb.dart';
import '../services/voice_setup.dart';

/// Full-screen hands-free voice mode. It starts the call when it opens and
/// hangs up when it closes. Every turn is also written into the chat.
class VoiceModeScreen extends StatefulWidget {
  const VoiceModeScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<VoiceModeScreen> createState() => _VoiceModeScreenState();
}

class _VoiceModeScreenState extends State<VoiceModeScreen> {
  bool _captions = true;

  CallController get call => widget.services.call;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => call.start());
  }

  @override
  void dispose() {
    if (call.inCall) call.hangUp();
    super.dispose();
  }

  Future<void> _hangUp() async {
    await call.hangUp();
    if (mounted) Navigator.of(context).maybePop();
  }

  String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  (OrbState, String, String) _look(AppLocalizations l) => switch (call.state) {
    CallState.idle => (OrbState.idle, l.callEnded, ''),
    CallState.connecting => (OrbState.idle, l.connecting, ''),
    CallState.listening => (OrbState.live, l.listening, l.speakNow),
    CallState.thinking => (OrbState.paused, l.thinking, l.tapToInterrupt),
    CallState.speaking => (OrbState.speaking, l.speaking, l.tapToInterrupt),
    CallState.error => (OrbState.idle, l.somethingWentWrong, ''),
  };

  void _onOrbTap() {
    switch (call.state) {
      case CallState.thinking || CallState.speaking:
        call.interrupt();
      case CallState.idle || CallState.error:
        call.start();
      case CallState.connecting || CallState.listening:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final sv = widget.services;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && call.inCall) call.hangUp();
      },
      child: Scaffold(
        backgroundColor: s.surface,
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: Brushes.soft),
              ),
            ),
            SafeArea(
              child: ListenableBuilder(
                listenable: Listenable.merge([call, sv.settings, sv.speaker]),
                builder: (context, _) {
                  final l = context.l10n;
                  final (orb, status, hint) = _look(l);
                  final canInterrupt =
                      call.state == CallState.thinking ||
                      call.state == CallState.speaking;
                  final ended = !call.inCall;
                  return Column(
                    children: [
                      PageTitle(
                        title: l.voiceModeTitle,
                        maxLines: 1,
                        leading: IconButton(
                          tooltip: l.closeVoiceMode,
                          onPressed: _hangUp,
                          icon: const HeroIcon(HeroIcons.chevronDown),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final orbPart = ActionOrb(
                              state: orb,
                              clock: _clock(call.elapsed),
                              hint: hint,
                              semanticLabel: status,
                              onTap: _onOrbTap,
                            );
                            final info = <Widget>[
                              Text(
                                status,
                                style: t.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: Space.sm),
                              AnimatedOpacity(
                                duration: Motion.fade,
                                opacity:
                                    call.state == CallState.listening ||
                                        call.state == CallState.speaking
                                    ? 1
                                    : 0.25,
                                // Mic levels arrive many times a second:
                                // only the waveform listens to them.
                                child: ValueListenableBuilder<double>(
                                  valueListenable: call.levels,
                                  builder: (context, level, _) => Waveform(
                                    level: call.state == CallState.listening
                                        ? level
                                        : 0,
                                    synthetic: call.state == CallState.speaking,
                                    color: call.state == CallState.listening
                                        ? Accent.red
                                        : s.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: Space.gutter),
                              if (call.error != null)
                                _errorCard(context, call.error!),
                              if (_captions) _captionCard(context),
                              const SizedBox(height: Space.gutter),
                            ];
                            // Short and wide (a phone on its side, split
                            // screen): orb on the left, words on the right.
                            final sideBySide =
                                box.maxWidth > box.maxHeight &&
                                box.maxHeight < 480 &&
                                box.maxWidth >= 560;
                            if (sideBySide) {
                              return Row(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: orbPart,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.only(
                                        right: Space.gutter,
                                      ),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: box.maxHeight,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: info,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                            return SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: box.maxHeight,
                                ),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: Layout.maxWidthPage,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const SizedBox(height: Space.gutter),
                                        orbPart,
                                        const SizedBox(height: Space.s18),
                                        ...info,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: CircleAction(
                                icon: HeroIcons.handRaised,
                                label: l.interrupt,
                                accent: Accent.amber,
                                onTap: canInterrupt ? call.interrupt : null,
                              ),
                            ),
                            Expanded(
                              child: ended
                                  ? CircleAction(
                                      icon: HeroIcons.phone,
                                      label: l.callAgain,
                                      accent: Accent.teal,
                                      big: true,
                                      onTap: call.start,
                                    )
                                  : CircleAction(
                                      icon: HeroIcons.phoneXMark,
                                      label: l.hangUp,
                                      accent: Accent.red,
                                      big: true,
                                      onTap: _hangUp,
                                    ),
                            ),
                            Expanded(
                              child: CircleAction(
                                icon: HeroIcons.chatBubbleLeftRight,
                                label: _captions ? l.hideText : l.showText,
                                accent: Accent.green,
                                onTap: () =>
                                    setState(() => _captions = !_captions),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _captionCard(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final listening = call.state == CallState.listening;
    final you = listening ? call.partial : call.lastHeard;
    final reply = listening ? '' : (call.lastReply?.text ?? '');
    if (you.isEmpty && reply.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.emptyH),
        child: Text(
          call.inCall ? context.l10n.callStartHint : context.l10n.callSavedHint,
          textAlign: TextAlign.center,
          style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
        ),
      );
    }
    // Like the chat: what you said sits on the right, the reply on the left.
    return SizedBox(
      key: const ValueKey('captions'),
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Column(
          children: [
            if (you.isNotEmpty)
              _captionBubble(
                context,
                label: context.l10n.youLabel,
                labelColor: s.onSurfaceVariant,
                text: you,
                maxLines: 3,
                user: true,
              ),
            if (you.isNotEmpty && reply.isNotEmpty)
              const SizedBox(height: Space.ml),
            if (reply.isNotEmpty)
              _captionBubble(
                context,
                label: context.l10n.assistantLabel,
                labelColor: s.primary,
                text: reply,
                maxLines: 6,
                user: false,
              ),
          ],
        ),
      ),
    );
  }

  Widget _captionBubble(
    BuildContext context, {
    required String label,
    required Color labelColor,
    required String text,
    required int maxLines,
    required bool user,
  }) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    const r = Radius.circular(Radii.card);
    const tail = Radius.circular(6);
    return Align(
      alignment: user
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: LayoutBuilder(
        builder: (context, box) => ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: box.maxWidth * ChatLayout.userBubbleMax,
          ),
          child: Column(
            crossAxisAlignment: user
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  label,
                  style: t.labelSmall?.copyWith(
                    color: labelColor,
                    letterSpacing: tracking(context, 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                key: ValueKey(user ? 'caption-you' : 'caption-reply'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: user ? s.primaryContainer : s.surfaceContainer,
                  border: user ? null : Border.all(color: s.outlineVariant),
                  borderRadius: BorderRadiusDirectional.only(
                    topStart: r,
                    topEnd: r,
                    bottomStart: user ? r : tail,
                    bottomEnd: user ? tail : r,
                  ),
                ),
                child: Text(
                  text,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyLarge?.copyWith(
                    color: user ? s.onPrimaryContainer : s.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context, String error) {
    final s = Theme.of(context).colorScheme;
    final needsVoice = error == context.l10n.noBanglaVoicesTitle;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.ml),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Layout.maxWidthPage),
        child: AppCard(
          borderColor: s.error.withValues(alpha: Alphas.circleActionBorder),
          child: SettingRow(
            icon: HeroIcons.exclamationTriangle,
            accent: Accent.red,
            title: error,
            onTap: needsVoice
                ? () => VoiceSetupFix.open(widget.services.speaker.setup)
                : null,
          ),
        ),
      ),
    );
  }
}
