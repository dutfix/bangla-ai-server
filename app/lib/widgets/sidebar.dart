import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../models/chat.dart';
import '../services/chat_store.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import 'components.dart';

/// Chat history: new chat, search, chats grouped by day, rename and delete,
/// and links to Voices and Settings.
class ChatSidebar extends StatefulWidget {
  const ChatSidebar({
    super.key,
    required this.store,
    required this.currentId,
    required this.onNewChat,
    required this.onOpen,
    required this.onDeleted,
    required this.onVoices,
    required this.onSettings,
  });

  final ChatStore store;
  final String? currentId;
  final VoidCallback onNewChat;
  final ValueChanged<Conversation> onOpen;
  final ValueChanged<Conversation> onDeleted;
  final VoidCallback onVoices;
  final VoidCallback onSettings;

  @override
  State<ChatSidebar> createState() => _ChatSidebarState();
}

class _ChatSidebarState extends State<ChatSidebar> {
  String _query = '';

  static String groupOf(DateTime d, DateTime now, AppLocalizations l10n) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return l10n.groupToday;
    if (diff == 1) return l10n.groupYesterday;
    if (diff < 7) return l10n.groupPrevious7;
    if (diff < 30) return l10n.groupPrevious30;
    if (d.year == now.year) return l10n.monthNames.split(',')[d.month - 1];
    return localDigits('${d.year}', l10n.localeName);
  }

  Future<void> _rename(Conversation c) async {
    final name = await showTextDialog(
      context,
      title: context.l10n.renameChat,
      initial: c.title,
      confirm: context.l10n.rename,
    );
    if (name != null && name.trim().isNotEmpty) {
      widget.store.rename(c, name);
    }
  }

  Future<void> _delete(Conversation c) async {
    final ok = await showConfirmDialog(
      context,
      title: context.l10n.deleteChatTitle,
      body: context.l10n.deleteChatBody(chatTitle(c.title, context.l10n)),
      confirm: context.l10n.delete,
      destructive: true,
    );
    if (!ok) return;
    widget.store.delete(c);
    widget.onDeleted(c);
  }

  Future<void> _menu(Conversation c) async {
    final s = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                chatTitle(c.title, ctx.l10n),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            SettingRow(
              icon: HeroIcons.pencil,
              accent: Accent.green,
              title: ctx.l10n.rename,
              showChevron: false,
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            SettingRow(
              icon: HeroIcons.trash,
              accent: Accent.red,
              title: ctx.l10n.delete,
              titleColor: s.error,
              showChevron: false,
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'rename') await _rename(c);
    if (choice == 'delete') await _delete(c);
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Material(
      color: s.surfaceContainerLow,
      child: SafeArea(
        right: false,
        child: LayoutBuilder(
          builder: (context, box) {
            // On short screens (phones in landscape) the links scroll with
            // the list instead of taking fixed space.
            final compact = box.maxHeight < 520;
            final footer = [
              _footerRow(
                icon: HeroIcons.speakerWave,
                accent: Accent.green,
                label: context.l10n.voices,
                onTap: widget.onVoices,
              ),
              _footerRow(
                icon: HeroIcons.cog6Tooth,
                accent: Accent.flagRed,
                label: context.l10n.settings,
                onTap: widget.onSettings,
              ),
              const SizedBox(height: Space.sm),
            ];
            if (compact) {
              return ListenableBuilder(
                listenable: widget.store,
                builder: (context, _) => ListView(
                  children: [
                    ..._header(),
                    ..._items(s, t),
                    Divider(color: s.outlineVariant),
                    ...footer,
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._header(),
                Expanded(
                  child: ListenableBuilder(
                    listenable: widget.store,
                    builder: (context, _) => ListView(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      children: _items(s, t),
                    ),
                  ),
                ),
                Divider(color: s.outlineVariant),
                ...footer,
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _header() => [
    PageTitle(title: context.l10n.appName, maxLines: 1),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: PrimaryButton(
        label: context.l10n.newChat,
        icon: HeroIcons.pencilSquare,
        expand: true,
        onPressed: widget.onNewChat,
      ),
    ),
    SearchField(
      hint: context.l10n.searchChats,
      onChanged: (v) => setState(() => _query = v),
    ),
  ];

  Widget _footerRow({
    required HeroIconData icon,
    required Color accent,
    required String label,
    required VoidCallback onTap,
  }) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.tile),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              IconBadge(icon: icon, accent: accent),
              const SizedBox(width: Space.l),
              Expanded(child: Text(label, style: t.titleMedium)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _items(ColorScheme s, TextTheme t) {
    final hits = widget.store.search(_query);
    if (hits.isEmpty) {
      return [
        EmptyState(
          icon: _query.isEmpty
              ? HeroIcons.chatBubbleLeftRight
              : HeroIcons.magnifyingGlass,
          title: _query.isEmpty
              ? context.l10n.noChatsYet
              : context.l10n.noMatches,
          sub: _query.isEmpty
              ? context.l10n.chatsSavedHere
              : context.l10n.nothingMatches(_query),
        ),
      ];
    }
    final now = DateTime.now();
    final items = <Widget>[];
    String? group;
    for (final h in hits) {
      final g = _query.isEmpty
          ? groupOf(h.conversation.updated, now, context.l10n)
          : context.l10n.results;
      if (g != group) {
        group = g;
        items.add(SectionTitle(g, top: items.isEmpty ? 14 : 18));
      }
      items.add(_row(h, s, t));
    }
    return items;
  }

  Widget _row(ChatSearchHit h, ColorScheme s, TextTheme t) {
    final c = h.conversation;
    final selected = c.id == widget.currentId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected
            ? s.primary.withValues(alpha: Alphas.selectedRow)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.tile),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onOpen(c),
          onLongPress: () => _menu(c),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chatTitle(c.title, context.l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall?.copyWith(
                          color: selected ? s.primary : s.onSurface,
                        ),
                      ),
                      if (h.snippet != null)
                        Text(
                          h.snippet!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(
                            color: s.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: context.l10n.chatOptions,
                  icon: HeroIcon(
                    HeroIcons.ellipsisHorizontal,
                    size: 20,
                    color: s.onSurfaceVariant,
                  ),
                  onSelected: (v) {
                    if (v == 'rename') _rename(c);
                    if (v == 'delete') _delete(c);
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          const HeroIcon(HeroIcons.pencil, size: 20),
                          const SizedBox(width: Space.ml),
                          Text(context.l10n.rename, style: t.bodyLarge),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          HeroIcon(HeroIcons.trash, size: 20, color: s.error),
                          const SizedBox(width: Space.ml),
                          Text(
                            context.l10n.delete,
                            style: t.bodyLarge?.copyWith(color: s.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Used by tests.
@visibleForTesting
String sidebarGroupOf(DateTime d, DateTime now, AppLocalizations l10n) =>
    _ChatSidebarState.groupOf(d, now, l10n);
