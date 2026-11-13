import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../l10n/l10n.dart';
import '../services/settings_store.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/model_sheet.dart';

/// User settings. There is nothing to connect: the AI connection, the models
/// and the default voice are set by the admin on the server.
/// Shown in About; keep in step with pubspec.yaml.
const appVersion = '1.1.0';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsStore get s => widget.services.settings;

  @override
  void initState() {
    super.initState();
    widget.services.speaker.init();
  }

  @override
  Widget build(BuildContext context) {
    final sc = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final l = context.l10n;
    final themeNames = {
      ThemeMode.system: l.themeSystem,
      ThemeMode.light: l.themeLight,
      ThemeMode.dark: l.themeDark,
    };
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([s, widget.services.speaker]),
        builder: (context, _) => PinnedPage(
          title: l.settings,
          onBack: () => Navigator.of(context).maybePop(),
          children: [
            SectionTitle(l.language, top: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                l.languageSub,
                style: t.bodyMedium?.copyWith(color: sc.onSurfaceVariant),
              ),
            ),
            ChipRow(
              children: [
                for (final code in AppLanguage.codes)
                  ChipButton(
                    label: AppLanguage.nativeName(code),
                    icon: HeroIcons.language,
                    selected: s.language == code,
                    onPressed: () => s.setLanguage(code),
                  ),
              ],
            ),
            // The admin sets the model; users only see a picker when the
            // admin offers more than one.
            if (hasModelChoice(s)) ...[
              SectionTitle(l.model),
              AppCard(
                child: SettingRow(
                  icon: HeroIcons.cpuChip,
                  accent: Accent.green,
                  title: l.model,
                  value: modelLabel(s.model, l),
                  onTap: () => showModelSheet(context, s),
                ),
              ),
            ],
            SectionTitle(l.appearance),
            ChipRow(
              children: [
                for (final m in ThemeMode.values)
                  ChipButton(
                    label: themeNames[m]!,
                    icon: switch (m) {
                      ThemeMode.system => HeroIcons.computerDesktop,
                      ThemeMode.light => HeroIcons.sun,
                      ThemeMode.dark => HeroIcons.moon,
                    },
                    selected: s.themeMode == m,
                    onPressed: () => s.setThemeMode(m),
                  ),
              ],
            ),
            SectionTitle(l.chats),
            AppCard(
              child: SettingRow(
                icon: HeroIcons.trash,
                accent: Accent.red,
                title: l.deleteAllChats,
                sub: l.deleteAllChatsSub,
                titleColor: sc.error,
                showChevron: false,
                onTap: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: l.deleteAllChatsTitle,
                    body: l.deleteAllChatsBody,
                    confirm: l.deleteAll,
                    destructive: true,
                  );
                  if (!ok) return;
                  widget.services.chat.newChat();
                  widget.services.chats.deleteAll();
                  if (context.mounted) showSnack(context, l.allChatsDeleted);
                },
              ),
            ),
            SectionTitle(l.about),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${l.aboutVersion(localDigits(appVersion))}\n\n${l.aboutSpeech}',
                style: t.bodyMedium?.copyWith(color: sc.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
