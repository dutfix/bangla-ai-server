import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../services/settings_store.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';

/// A model's name as users read it: the routing presets get a translated
/// name, real model ids are shown as they are.
String modelLabel(String m, AppLocalizations l) => switch (m) {
  'auto' => l.modelAuto,
  'auto/fast' => l.modelFast,
  _ => m,
};

/// Whether users get a model picker: only when the admin offers a choice.
bool hasModelChoice(SettingsStore settings) => settings.models.length > 1;

/// The model picker: one of the models the admin offers on the server.
Future<void> showModelSheet(BuildContext context, SettingsStore settings) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ModelSheet(settings: settings),
  );
}

class _ModelSheet extends StatelessWidget {
  const _ModelSheet({required this.settings});
  final SettingsStore settings;

  String? _describe(BuildContext context, String m) => switch (m) {
    'auto' => context.l10n.modelAutoDesc,
    'auto/fast' => context.l10n.modelAutoFastDesc,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final l = context.l10n;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => SafeArea(
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
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(l.model, style: t.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  l.modelSheetHelpServer,
                  style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    for (final m in settings.models)
                      _row(context, m, scheme, t),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String m, ColorScheme scheme, TextTheme t) {
    final selected = m == settings.model;
    final isDefault = m == settings.remote.defaultModel;
    final sub = [
      ?_describe(context, m),
      if (isDefault) context.l10n.defaultTag,
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: Alphas.selectedRow)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.tile),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await settings.setModel(m);
            if (context.mounted) Navigator.pop(context);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        modelLabel(m, context.l10n),
                        style: t.titleMedium?.copyWith(
                          color: selected ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                      if (sub.isNotEmpty)
                        Text(
                          sub,
                          style: t.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (selected)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: HeroIcon(HeroIcons.check, color: scheme.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
