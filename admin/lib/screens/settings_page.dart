import 'package:material_ui/material_ui.dart';

import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/form_bits.dart';
import 'dashboard_screen.dart';

/// Shown in Settings; keep in step with pubspec.yaml.
const adminVersion = '1.2.0';

/// The Settings tab: the app's on/off switch, the account, the server.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.ctx});
  final AdminContext ctx;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    final ed = ctx.editor;
    return PinnedPage(
      title: 'Settings',
      sub: 'The app, your account and the server',
      children: [
        StoreWarning(editor: ed),
        const SectionTitle('The Bangla AI app', top: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchRow(
                icon: HeroIcons.signal,
                accent: ed.enabled ? Accent.green : Accent.red,
                title: 'App is on',
                sub: ed.enabled
                    ? 'Users can chat.'
                    : 'Users see the message below instead of replies.',
                value: ed.enabled,
                onChanged: (v) => ed.edit(() => ed.enabled = v),
              ),
              Field(
                ed.disabledMessage,
                'Message when the app is off',
                maxLines: 3,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),

        const SectionTitle('Account'),
        AppCard(
          child: Column(
            children: [
              SettingRow(
                icon: HeroIcons.envelope,
                accent: sc.primary,
                title: 'Signed in',
                sub: ctx.api.lastEmail.isEmpty ? 'Admin' : ctx.api.lastEmail,
                showChevron: false,
              ),
              SettingRow(
                icon: HeroIcons.arrowTopRightOnSquare,
                accent: Accent.red,
                title: 'Sign out',
                titleColor: sc.error,
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Sign out?'),
                      content: const Text(
                        'You will need a new email code to sign in again.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await ctx.signOut();
                },
              ),
            ],
          ),
        ),

        const SectionTitle('Server'),
        AppCard(
          child: Column(
            children: [
              SettingRow(
                icon: HeroIcons.serverStack,
                accent: Accent.teal,
                title: 'Address',
                sub: ctx.host,
                showChevron: false,
              ),
              SettingRow(
                icon: HeroIcons.arrowPath,
                accent: sc.primary,
                title: 'Reload settings from the server',
                sub: 'Drops unsaved changes.',
                onTap: ctx.reload,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Text(
            'Bangla AI Admin $adminVersion',
            style: t.bodySmall?.copyWith(color: sc.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
