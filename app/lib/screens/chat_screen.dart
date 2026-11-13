import 'package:material_ui/material_ui.dart';

import 'dart:async';

import '../app_services.dart';
import '../l10n/l10n.dart';
import '../services/settings_store.dart';
import '../services/speaker.dart';
import '../services/voice_setup.dart';
import '../models/chat.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/composer.dart';
import '../widgets/message_tile.dart';
import '../widgets/model_sheet.dart';
import '../widgets/sidebar.dart';
import 'settings_screen.dart';
import 'voice_mode_screen.dart';

/// The main screen: chat history on the side (a drawer on phones, fixed at
/// 600dp and wider), the conversation, and the composer.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  // Scroll state lives in notifiers so scrolling rebuilds only the jump
  // button and the divider, never the whole screen.
  final _showJump = ValueNotifier(false);
  final _scrolled = ValueNotifier(false);

  AppServices get sv => widget.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fetch the admin's config (wakes the free server if it sleeps).
    unawaited(sv.settings.refreshRemote());
    unawaited(sv.speaker.init());
    _scroll.addListener(() {
      // The list is reversed: offset 0 is the newest message.
      final jump = _scroll.hasClients && _scroll.offset > 400;
      final scrolled =
          _scroll.hasClients &&
          _scroll.position.maxScrollExtent - _scroll.offset > 1;
      _showJump.value = jump;
      _scrolled.value = scrolled;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(sv.settings.refreshRemote());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    _showJump.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  /// The chat history stays open beside the chat on tablets and unfolded
  /// foldables. A phone on its side is wide but short, so it keeps the
  /// drawer and gives the chat the whole width.
  bool get _wide {
    final size = MediaQuery.sizeOf(context);
    return size.width >= Layout.railBreakpoint &&
        (size.height >= Layout.railMinHeight ||
            size.width >= Layout.railAlwaysWidth);
  }

  void _closeDrawer() {
    if (_scaffold.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _newChat() {
    sv.readAloud.stop();
    sv.chat.newChat();
    _input.clear();
    _closeDrawer();
  }

  void _open(Conversation c) {
    sv.readAloud.stop();
    sv.chat.open(c);
    _closeDrawer();
    _jumpToEnd();
  }

  void _jumpToEnd() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: Motion.fade, curve: Curves.easeOut);
    }
  }

  Future<void> _push(Widget page) async {
    _closeDrawer();
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _send(String text) {
    sv.readAloud.stop();
    sv.chat.send(text);
    _jumpToEnd();
  }

  Future<void> _voiceCall() async {
    _focus.unfocus();
    await sv.readAloud.stop();
    sv.chat.stop();
    if (!mounted) return;
    if (!sv.settings.isConfigured) {
      final r = sv.settings.remote;
      showSnack(
        context,
        r.disabledMessage.isNotEmpty
            ? r.disabledMessage
            : context.l10n.appDisabled,
      );
      return;
    }
    if (!sv.settings.voiceEnabled) {
      showSnack(context, context.l10n.voiceOff);
      return;
    }
    if (!sv.settings.cloudVoice && (!await _voiceSetupCheck() || !mounted)) {
      return;
    }
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => VoiceModeScreen(services: sv),
        transitionsBuilder: (context, a, _, child) {
          final curved = CurvedAnimation(parent: a, curve: Curves.easeOut);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(
                begin: Motion.screenEnterScaleFrom,
                end: 1.0,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    _jumpToEnd();
  }

  Future<void> _speak(ChatMessage m) async {
    if (sv.readAloud.isReading(m.id)) {
      await sv.readAloud.stop();
      return;
    }
    try {
      await sv.readAloud.read(m.id, m.text);
    } catch (e) {
      if (!mounted) return;
      showSnack(
        context,
        context.l10n.couldNotReadAloud(
          e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  Widget? _serverBanner(BuildContext context) {
    final st = sv.settings;
    final l = context.l10n;
    if (!st.remote.enabled) {
      return _Banner(
        text: st.remote.disabledMessage.isNotEmpty
            ? st.remote.disabledMessage
            : l.appDisabled,
        icon: HeroIcons.handRaised,
        accent: Accent.amber,
        onRetry: st.refreshRemote,
      );
    }
    return switch (st.serverState) {
      ServerState.waking => _Banner(
        text: l.serverWaking,
        icon: HeroIcons.clock,
        accent: Accent.teal,
        busy: true,
      ),
      ServerState.offline => _Banner(
        text: l.serverOffline,
        icon: HeroIcons.signal,
        accent: Accent.red,
        onRetry: st.refreshRemote,
      ),
      _ => null,
    };
  }

  /// Before the first call: offer to install Google's Bangla voice when the
  /// phone lacks it. Asked once; the call goes ahead either way.
  Future<bool> _voiceSetupCheck() async {
    final st = sv.settings;
    if (st.voiceSetupPrompted) return true;
    await sv.speaker.init();
    final setup = sv.speaker.setup;
    if (setup == VoiceSetup.ready || !mounted) return true;
    await st.markVoiceSetupPrompted();
    if (!mounted) return true;
    final l = context.l10n;
    final noGoogle = setup == VoiceSetup.noGoogleEngine;
    final fix = await showConfirmDialog(
      context,
      title: noGoogle ? l.setupNoGoogleTitle : l.setupNoBanglaTitle,
      body: noGoogle ? l.setupNoGoogleBody : l.setupNoBanglaBody,
      confirm: noGoogle ? l.setupNoGoogleButton : l.setupNoBanglaButton,
    );
    if (!fix) return true;
    final ok = await VoiceSetupFix.open(setup);
    if (!ok && mounted) showSnack(context, l.setupCouldNotOpen);
    return false;
  }

  Widget _sidebar() => ListenableBuilder(
    listenable: sv.chat,
    builder: (context, _) => ChatSidebar(
      store: sv.chats,
      currentId: sv.chat.current?.id,
      onNewChat: _newChat,
      onOpen: _open,
      onDeleted: sv.chat.forget,
      onSettings: () => _push(SettingsScreen(services: sv)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final wide = _wide;
    final body = _chatBody(context, wide);
    return Scaffold(
      key: _scaffold,
      backgroundColor: s.surface,
      resizeToAvoidBottomInset: true,
      drawer: wide ? null : Drawer(child: _sidebar()),
      drawerEdgeDragWidth: 40,
      body: wide
          ? Row(
              children: [
                SizedBox(width: Layout.sidebarWidth, child: _sidebar()),
                VerticalDivider(width: 1, color: s.outlineVariant),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }

  Widget _chatBody(BuildContext context, bool wide) {
    return ListenableBuilder(
      listenable: Listenable.merge([sv.chat, sv.settings, sv.readAloud]),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, box) => _chatColumn(context, wide, box.maxHeight),
        );
      },
    );
  }

  Widget _chatColumn(BuildContext context, bool wide, double height) {
    final s = Theme.of(context).colorScheme;
    final chat = sv.chat;
    final empty = chat.messages.isEmpty;
    // [height] is what the Scaffold leaves the chat, keyboard already
    // taken off; the system bars come off here.
    final mq = MediaQuery.of(context);
    final room = height - mq.padding.vertical;
    final cramped = room < 460;
    Widget chrome(Widget child) => cramped
        ? MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
            ),
            child: child,
          )
        : child;
    return Column(
      children: [
        chrome(
          SafeArea(
            bottom: false,
            left: !wide,
            child: _TopBar(
              wide: wide,
              model: hasModelChoice(sv.settings)
                  ? modelLabel(sv.settings.model, context.l10n)
                  : null,
              title: chat.current?.title,
              onMenu: () => _scaffold.currentState?.openDrawer(),
              onModel: hasModelChoice(sv.settings)
                  ? () => showModelSheet(context, sv.settings)
                  : null,
              onNewChat: empty ? null : _newChat,
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _scrolled,
          builder: (context, scrolled, child) => AnimatedOpacity(
            opacity: scrolled && !empty ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: child,
          ),
          child: Divider(color: s.outlineVariant),
        ),
        Expanded(
          child: empty
              ? _Welcome(
                  onVoiceCall: sv.settings.voiceEnabled ? _voiceCall : null,
                  onSuggestion: (text) {
                    _input.text = text;
                    _input.selection = TextSelection.collapsed(
                      offset: text.length,
                    );
                    _focus.requestFocus();
                  },
                )
              : Stack(
                  children: [
                    _messageList(context),
                    ValueListenableBuilder(
                      valueListenable: _showJump,
                      builder: (context, show, child) =>
                          show ? child! : const SizedBox.shrink(),
                      child: Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Material(
                            color: s.surfaceContainer,
                            shape: CircleBorder(
                              side: BorderSide(color: s.outlineVariant),
                            ),
                            child: IconButton(
                              tooltip: context.l10n.jumpToLatest,
                              onPressed: _jumpToEnd,
                              icon: const HeroIcon(HeroIcons.arrowDown),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        // Banners and the message box never take more than 60% of the
        // height; past that they scroll, so the column cannot overflow.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: room * 0.6),
          child: SingleChildScrollView(
            reverse: true,
            physics: const ClampingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ?_serverBanner(context),
                if (chat.notice != null)
                  _Notice(
                    text: chat.notice!,
                    onSettings: () => _push(SettingsScreen(services: sv)),
                  ),
                chrome(
                  SafeArea(
                    top: false,
                    left: !wide,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: Layout.maxWidthPage,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                          child: Composer(
                            controller: _input,
                            focusNode: _focus,
                            generating: chat.generating,
                            onSend: _send,
                            onStop: chat.stop,
                            onVoiceCall: sv.settings.voiceEnabled
                                ? _voiceCall
                                : null,
                            maxLines: room < 300 ? 2 : (cramped ? 3 : 6),
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
      ],
    );
  }

  Widget _messageList(BuildContext context) {
    final chat = sv.chat;
    final list = chat.messages;
    final lastReply = list.lastWhere(
      (m) => !m.isUser,
      orElse: () => ChatMessage(role: Role.user),
    );
    final busy = chat.generating || sv.call.inCall;
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final m = list[list.length - 1 - i];
        Widget tile() => MessageTile(
          key: ValueKey(m.id),
          message: m,
          streaming:
              identical(chat.streaming, m) ||
              (sv.call.inCall && identical(sv.call.lastReply, m)),
          isLastReply: identical(m, lastReply) && m == list.last,
          reading: sv.readAloud.isReading(m.id),
          busy: busy,
          onRegenerate: () => chat.regenerate(m),
          onEdit: (text) => chat.editAndResend(m, text),
          onSpeak: sv.settings.voiceEnabled ? () => _speak(m) : null,
        );
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Layout.maxWidthPage),
            // Only the newest message can still be growing: it alone
            // rebuilds as a reply streams in.
            child: i == 0
                ? ListenableBuilder(
                    listenable: chat.replyTicks,
                    builder: (context, _) => tile(),
                  )
                : tile(),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.wide,
    required this.model,
    required this.title,
    required this.onMenu,
    required this.onModel,
    required this.onNewChat,
  });

  final bool wide;

  /// The model's display name, or null when users get no model picker.
  final String? model;
  final String? title;
  final VoidCallback onMenu;
  final VoidCallback? onModel;
  final VoidCallback? onNewChat;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final subtitle = (title != null && title!.isNotEmpty) ? title : model;
    // At least 64dp, and taller when the system font is large. The title is
    // a display face, so its growth is capped to keep the bar compact.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            if (!wide)
              IconButton(
                tooltip: context.l10n.chats,
                onPressed: onMenu,
                icon: const HeroIcon(HeroIcons.bars3),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: wide ? Alignment.centerLeft : Alignment.center,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.button),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onModel,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: wide
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Shrinks to fit rather than cutting the
                              // app's name on narrow screens.
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    context.l10n.appName.toUpperCase(),
                                    maxLines: 1,
                                    style: t.headlineLarge,
                                    textScaler: MediaQuery.textScalerOf(context)
                                        .clamp(maxScaleFactor: 1.3),
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(left: 6, top: 3),
                                child: TitleDot(),
                              ),
                              if (onModel != null) ...[
                                const SizedBox(width: 4),
                                HeroIcon(
                                  HeroIcons.chevronDown,
                                  size: 18,
                                  color: s.onSurfaceVariant,
                                ),
                              ],
                            ],
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall?.copyWith(
                                color: s.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: context.l10n.newChat,
              onPressed: onNewChat,
              icon: HeroIcon(
                HeroIcons.pencilSquare,
                color: onNewChat == null
                    ? s.onSurfaceVariant.withValues(alpha: 0.4)
                    : s.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({this.onVoiceCall, required this.onSuggestion});

  /// Null when the admin has voice off: no call card.
  final VoidCallback? onVoiceCall;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final l = context.l10n;
    final suggestions = [
      (HeroIcons.lightBulb, l.suggestExplain, l.suggestExplainPrompt),
      (HeroIcons.codeBracket, l.suggestCode, l.suggestCodePrompt),
      (HeroIcons.documentText, l.suggestSummarize, l.suggestSummarizePrompt),
      (HeroIcons.sparkles, l.suggestBrainstorm, l.suggestBrainstormPrompt),
    ];
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Layout.maxWidthPage),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AssistantAvatar(size: 56)),
                    const SizedBox(height: Space.gutter),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.textInset,
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: l.howCanIHelp),
                            const WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: EdgeInsets.only(left: 6, top: 6),
                                child: TitleDot(),
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: t.displaySmall,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.textInset,
                      ),
                      child: Text(
                        l.emptyChatSub,
                        textAlign: TextAlign.center,
                        style: t.bodyMedium?.copyWith(
                          color: s.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.gutter),
                    if (onVoiceCall != null) ...[
                      HeroCard(
                        title: l.startVoiceCall,
                        sub: l.startVoiceCallSub,
                        icon: HeroCustom.waveform,
                        onTap: onVoiceCall!,
                      ),
                      const SizedBox(height: Space.sm),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.gutter,
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: Space.rowGap,
                        runSpacing: Space.rowGap,
                        children: [
                          for (final (icon, label, text) in suggestions)
                            ChipButton(
                              label: label,
                              icon: icon,
                              iconColor: s.primary,
                              onPressed: () => onSuggestion(text),
                            ),
                        ],
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

/// "Server is waking up", "offline" or "paused by the admin".
class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.icon,
    required this.accent,
    this.busy = false,
    this.onRetry,
  });
  final String text;
  final HeroIconData icon;
  final Color accent;
  final bool busy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.maxWidthPage),
          child: AppCard(
            borderColor: accent.withValues(alpha: 0.45),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              child: Row(
                children: [
                  if (busy)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: accent,
                      ),
                    )
                  else
                    HeroIcon(icon, size: 20, color: accent),
                  const SizedBox(width: 12),
                  Expanded(child: Text(text, style: t.bodyMedium)),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      child: Text(context.l10n.retryNow),
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

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.onSettings});
  final String text;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.maxWidthPage),
          child: AppCard(
            child: SettingRow(
              icon: HeroIcons.exclamationTriangle,
              accent: Accent.amber,
              title: text,
              onTap: onSettings,
            ),
          ),
        ),
      ),
    );
  }
}
