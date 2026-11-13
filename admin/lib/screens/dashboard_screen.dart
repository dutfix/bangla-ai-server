import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../state/editor.dart';
import '../theme/hero_icons.dart';
import '../widgets/components.dart';
import '../widgets/form_bits.dart';
import 'ai_page.dart';
import 'login_screen.dart';
import 'overview_page.dart';
import 'settings_page.dart';
import 'voice_page.dart';

/// The admin app after sign-in: a navigation bar (a side rail on wide
/// screens) with Overview, AI, Voice and Settings. Changes on any tab wait
/// in one draft until Save; every Bangla AI user gets them the next time
/// their app opens or comes back to the front. No app update needed.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.api, this.initialTab = 0});
  final AdminApi api;
  final int initialTab;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _Tab {
  const _Tab(this.label, this.icon);
  final String label;
  final HeroIconData icon;
}

const _tabs = [
  _Tab('Overview', HeroIcons.squares2x2),
  _Tab('AI', HeroIcons.sparkles),
  _Tab('Voice', HeroIcons.speakerWave),
  _Tab('Settings', HeroIcons.adjustmentsHorizontal),
];

class _DashboardScreenState extends State<DashboardScreen> {
  AdminApi get api => widget.api;
  late final Editor editor = Editor(api)..addListener(_changed);
  late int _tab = widget.initialTab;

  bool _loading = true;
  bool _waking = false;
  String? _loadError;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    editor.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final awake = await api.wake(
        onWaiting: () {
          if (mounted && !_waking) setState(() => _waking = true);
        },
      );
      if (!awake) {
        throw ApiException("Can't reach the server at ${api.baseUrl}.");
      }
      final (cfg, storeOk) = await api.getConfig();
      if (!mounted) return;
      editor.apply(cfg, stored: storeOk);
    } on ApiException catch (e) {
      if (e.signedOut) return signOut();
      if (mounted) setState(() => _loadError = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _waking = false;
        });
      }
    }
  }

  Future<void> _save() async {
    try {
      final msg = await editor.save();
      if (mounted) showSnack(context, msg);
    } on ApiException catch (e) {
      if (e.signedOut) return signOut();
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> signOut() async {
    await api.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => LoginScreen(api: api)),
      (_) => false,
    );
  }

  Widget _page() {
    final ctx = AdminContext(
      api: api,
      editor: editor,
      reload: _load,
      signOut: signOut,
      goTo: (i) => setState(() => _tab = i),
    );
    return switch (_tab) {
      0 => OverviewPage(ctx: ctx),
      1 => AiPage(ctx: ctx),
      2 => VoicePage(ctx: ctx),
      _ => SettingsPage(ctx: ctx),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_loading || editor.cfg == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _loading
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _waking
                              ? 'The server is waking up. This can take up to a minute...'
                              : 'Loading settings...',
                          textAlign: TextAlign.center,
                          style: t.bodyMedium,
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _loadError ?? 'Something went wrong.',
                          textAlign: TextAlign.center,
                          style: t.bodyLarge,
                        ),
                        const SizedBox(height: 16),
                        PrimaryButton(
                          label: 'Try again',
                          icon: HeroIcons.arrowPath,
                          onPressed: _load,
                        ),
                        TextButton(
                          onPressed: signOut,
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 720;
    final saveBar = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: editor.dirty
          ? Padding(
              key: const ValueKey('save'),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 736),
                  child: SaveBar(
                    saving: editor.saving,
                    onSave: _save,
                    onDiscard: editor.discard,
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('none')),
    );
    // The save bar sits in the bottom slot, so pop-up notes (snack bars)
    // float above it instead of covering "Save for all users".
    final body = KeyedSubtree(key: ValueKey(_tab), child: _page());

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.9,
                leading: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('Admin', style: t.titleMedium),
                ),
                destinations: [
                  for (final tab in _tabs)
                    NavigationRailDestination(
                      icon: HeroIcon(tab.icon),
                      label: Text(tab.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: body,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(top: false, child: saveBar),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          saveBar,
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              for (final tab in _tabs)
                NavigationDestination(
                  icon: HeroIcon(tab.icon),
                  label: tab.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What every tab needs from the shell.
class AdminContext {
  const AdminContext({
    required this.api,
    required this.editor,
    required this.reload,
    required this.signOut,
    required this.goTo,
  });
  final AdminApi api;
  final Editor editor;
  final Future<void> Function() reload;
  final Future<void> Function() signOut;
  final void Function(int tab) goTo;

  String get host => api.baseUrl.replaceFirst(RegExp(r'^https?://'), '');
}

/// A warning card for when the server can't reach its database.
class StoreWarning extends StatelessWidget {
  const StoreWarning({super.key, required this.editor});
  final Editor editor;

  @override
  Widget build(BuildContext context) {
    if (editor.storeOk) return const SizedBox.shrink();
    final sc = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppCard(
        borderColor: sc.error,
        child: Note(
          "The server can't reach its database. Changes last only until it restarts.",
          color: sc.error,
        ),
      ),
    );
  }
}
