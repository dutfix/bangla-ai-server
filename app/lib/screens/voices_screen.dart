import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../l10n/l10n.dart';
import '../models/voice.dart';
import '../services/speaker.dart';
import '../services/voice_setup.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import '../widgets/components.dart';

/// A voice's name for people: "Voice 2 · Bangla (Bangladesh)". The engine's
/// ids (bn-bd-x-ban-local) mean nothing to users.
String voiceLabel(
  VoiceOption? v,
  List<VoiceOption> voices,
  AppLocalizations l,
) {
  if (v == null) return l.phoneBestVoice;
  final i = voices.indexOf(v);
  if (i < 0) return v.name;
  return '${l.voiceNumbered(localDigits('${i + 1}'))} · '
      '${v.india ? l.langBanglaIndia : l.langBanglaBangladesh}';
}

/// Picks the call voice from the phone's Google Bangla voices, and helps
/// install Google's engine or its Bangla voice when they are missing.
class VoicesScreen extends StatefulWidget {
  const VoicesScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<VoicesScreen> createState() => _VoicesScreenState();
}

class _VoicesScreenState extends State<VoicesScreen>
    with WidgetsBindingObserver {
  Speaker get speaker => widget.services.speaker;
  bool _loading = true;
  VoiceOption? _playing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    speaker.stop();
    super.dispose();
  }

  /// Back from the Play Store or the voice settings: look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _load() async {
    await speaker.init();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      await speaker.init();
      await speaker.refresh();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _play(VoiceOption v, String label) async {
    final s = widget.services.settings;
    if (_playing == v) {
      await speaker.stop();
      setState(() => _playing = null);
      return;
    }
    setState(() => _playing = v);
    try {
      await speaker.test(
        v,
        context.l10n.voiceTestSample(label.split(' · ').first),
        speed: s.speed,
        pitch: s.pitch,
      );
    } catch (e) {
      if (mounted) showSnack(context, context.l10n.testFailed('$e'));
    }
    if (mounted && _playing == v) setState(() => _playing = null);
  }

  Future<void> _select(VoiceOption v, String label) async {
    await widget.services.settings.setVoice(v);
    if (mounted) showSnack(context, context.l10n.nowCallVoice(label));
  }

  Future<void> _fix(VoiceSetup setup) async {
    final ok = await VoiceSetupFix.open(setup);
    if (!ok && mounted) showSnack(context, context.l10n.setupCouldNotOpen);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final sc = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final android = !kIsWeb && Platform.isAndroid;
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([speaker, widget.services.settings]),
        builder: (context, _) {
          final s = widget.services.settings;
          final voices = speaker.voices;
          final current = s.voice != null && voices.contains(s.voice)
              ? s.voice
              : speaker.defaultVoice;
          return PinnedPage(
            title: l.voices,
            onBack: () => Navigator.of(context).maybePop(),
            actions: [
              IconButton(
                tooltip: l.refreshVoices,
                onPressed: _loading ? null : _refresh,
                icon: const HeroIcon(HeroIcons.arrowPath),
              ),
            ],
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  android ? l.voicesIntro : l.voiceUnavailableIos,
                  style: t.bodyMedium?.copyWith(color: sc.onSurfaceVariant),
                ),
              ),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(l.loadingVoices, style: t.bodyMedium),
                    ],
                  ),
                )
              else ...[
                if (android && speaker.setup != VoiceSetup.ready)
                  _SetupCard(setup: speaker.setup, onFix: _fix),
                if (voices.isEmpty && speaker.setup == VoiceSetup.ready)
                  EmptyState(
                    icon: HeroIcons.speakerXMark,
                    title: l.noBanglaVoicesTitle,
                    action: OutlineButton(
                      label: l.refreshVoices,
                      onPressed: _refresh,
                    ),
                  ),
                if (voices.isNotEmpty) ...[
                  SectionTitle(l.callVoice, top: 8),
                  AppCard(
                    child: Column(
                      children: [
                        for (final (i, v) in voices.indexed) ...[
                          if (i > 0)
                            Divider(
                              color: sc.outlineVariant,
                              indent: 16,
                              endIndent: 16,
                            ),
                          _VoiceRow(
                            voice: v,
                            label: voiceLabel(v, voices, l),
                            selected: v == current,
                            isDefault: v == speaker.defaultVoice,
                            playing: _playing == v,
                            onPlay: () => _play(v, voiceLabel(v, voices, l)),
                            onSelect: () =>
                                _select(v, voiceLabel(v, voices, l)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.setup, required this.onFix});
  final VoiceSetup setup;
  final void Function(VoiceSetup) onFix;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final noGoogle = setup == VoiceSetup.noGoogleEngine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        borderColor: Accent.amber.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.all(Space.ml),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconBadge(
                    icon: HeroIcons.arrowDownTray,
                    accent: Accent.amber,
                  ),
                  const SizedBox(width: Space.ml),
                  Expanded(
                    child: Text(
                      noGoogle ? l.setupNoGoogleTitle : l.setupNoBanglaTitle,
                      style: t.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                noGoogle ? l.setupNoGoogleBody : l.setupNoBanglaBody,
                style: t.bodyMedium,
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: noGoogle ? l.setupNoGoogleButton : l.setupNoBanglaButton,
                icon: HeroIcons.arrowDownTray,
                expand: true,
                onPressed: () => onFix(setup),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.voice,
    required this.label,
    required this.selected,
    required this.isDefault,
    required this.playing,
    required this.onPlay,
    required this.onSelect,
  });

  final VoiceOption voice;
  final String label;
  final bool selected;
  final bool isDefault;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final sc = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final tags = [
      voice.network ? l.voiceNetworkTag : l.voiceOfflineTag,
      if (voice.gender == VoiceGender.female) l.genderFemale,
      if (voice.gender == VoiceGender.male) l.genderMale,
      if (isDefault) l.voiceDefaultTag,
    ].join(' · ');
    return InkWell(
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            IconButton(
              tooltip: playing ? l.stop : l.play,
              onPressed: onPlay,
              icon: HeroIcon(
                playing ? HeroIcons.stopSolid : HeroIcons.playSolid,
                color: sc.primary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: t.titleMedium?.copyWith(
                      color: selected ? sc.primary : sc.onSurface,
                    ),
                  ),
                  Text(
                    tags,
                    style: t.bodySmall?.copyWith(color: sc.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Pill(
                  l.callVoicePill,
                  color: sc.primary,
                  textColor: sc.onPrimary,
                ),
              )
            else
              TextButton(onPressed: onSelect, child: Text(l.select)),
          ],
        ),
      ),
    );
  }
}
