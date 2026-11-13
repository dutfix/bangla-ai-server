import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../state/editor.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/form_bits.dart';
import 'dashboard_screen.dart';

const _sample = 'আসসালামু আলাইকুম! আমি বাংলা এআই। কেমন আছেন?';

/// The Voice tab: everything about voice lives here, not in the main app.
/// Voice is off until the admin turns it on. When on, the app speaks with
/// the phone's own Bangla voice (free) or a cloud voice the server fetches
/// (Microsoft Azure, Google Cloud, OpenAI-compatible, ElevenLabs...); the
/// provider's key stays on the server.
class VoicePage extends StatefulWidget {
  const VoicePage({super.key, required this.ctx, this.tts, this.player});
  final AdminContext ctx;
  final FlutterTts? tts;
  final AudioPlayer? player;

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  Editor get ed => widget.ctx.editor;
  late final FlutterTts _tts = widget.tts ?? FlutterTts();
  AudioPlayer? _player;
  List<VoiceType> _types = [];
  String? _typesError;
  List<({String name, String locale})> _phoneVoices = [];

  @override
  void initState() {
    super.initState();
    _loadTypes();
    _loadPhoneVoices();
  }

  @override
  void dispose() {
    _player?.dispose();
    unawaited(_tts.stop().catchError((_) => null));
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final t = await widget.ctx.api.voiceTypes();
      if (mounted) setState(() => _types = t);
    } on ApiException catch (e) {
      if (e.signedOut) return widget.ctx.signOut();
      if (mounted) setState(() => _typesError = e.message);
    }
  }

  Future<void> _loadPhoneVoices() async {
    try {
      final raw = await _tts.getVoices;
      final list = <({String name, String locale})>[];
      for (final v in (raw as List? ?? const [])) {
        if (v is! Map) continue;
        final name = '${v['name'] ?? ''}';
        final locale = '${v['locale'] ?? ''}';
        if (!locale.toLowerCase().startsWith('bn') &&
            !name.toLowerCase().startsWith('bn')) {
          continue;
        }
        list.add((name: name, locale: locale));
      }
      list.sort((a, b) => a.name.compareTo(b.name));
      if (mounted) setState(() => _phoneVoices = list);
    } catch (_) {}
  }

  VoiceType? _type(String t) {
    for (final x in _types) {
      if (x.type == t) return x;
    }
    return null;
  }

  /// What a provider still needs before it can speak, '' when ready.
  String _missing(Map<String, dynamic> p) {
    final def = _type('${p['type']}');
    if (def == null) return '';
    final out = <String>[];
    for (final f in def.fields.where((f) => f.required)) {
      final has = f.secret
          ? ('${p[f.key] ?? ''}'.trim().isNotEmpty ||
                (ed.savedKeyHint('${p['id']}').isNotEmpty &&
                    p['clearApiKey'] != true))
          : '${p[f.key] ?? ''}'.trim().isNotEmpty;
      if (!has) out.add(f.label);
    }
    return out.join(', ');
  }

  Future<void> _hearPhone() async {
    try {
      await _tts.stop();
      if (ed.voiceName.isNotEmpty) {
        await _tts.setVoice({'name': ed.voiceName, 'locale': ed.voiceLocale});
      } else {
        await _tts.setLanguage('bn-BD');
      }
      await _tts.setSpeechRate(ed.speed / 2);
      await _tts.setPitch(ed.pitch);
      await _tts.speak(_sample);
    } catch (e) {
      if (mounted) showSnack(context, 'This phone could not speak: $e');
    }
  }

  Future<void> _play(VoiceSample s) async {
    if (s.audio == null) return;
    try {
      final p = _player ??= widget.player ?? AudioPlayer();
      await p.stop();
      await p.play(BytesSource(s.audio!, mimeType: 'audio/mpeg'));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not play the sample: $e');
    }
  }

  Future<void> _pickPhoneVoice() async {
    final picked = await showChoiceSheet<String>(
      context,
      title: 'Phone voice',
      selected: ed.voiceName,
      options: [
        const ChoiceOption(
          '',
          'Best Bangla voice on each phone',
          sub: 'Recommended',
        ),
        for (final v in _phoneVoices)
          ChoiceOption(
            v.name,
            v.name,
            sub: [
              v.locale,
              if (v.name.contains('network')) 'needs internet, starts slower',
              if (v.name.contains('local')) 'works offline',
            ].join(' · '),
          ),
      ],
    );
    if (picked == null) return;
    ed.edit(() {
      ed.voiceName = picked;
      ed.voiceLocale = picked.isEmpty
          ? 'bn-BD'
          : _phoneVoices.firstWhere((v) => v.name == picked).locale;
    });
  }

  Future<void> _editProvider(Map<String, dynamic>? existing) async {
    if (_types.isEmpty) {
      return showSnack(
        context,
        _typesError ?? 'Loading the providers. Try again in a moment.',
      );
    }
    var type = existing == null ? null : _type('${existing['type']}');
    if (type == null) {
      final picked = await showChoiceSheet<String>(
        context,
        title: 'Add a voice provider',
        options: [
          for (final t in _types) ChoiceOption(t.type, t.label, sub: t.note),
        ],
      );
      if (picked == null || !mounted) return;
      type = _type(picked);
      if (type == null) return;
    }
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ProviderEditor(
          api: widget.ctx.api,
          type: type!,
          initial: existing,
          savedKeyHint: existing == null
              ? ''
              : ed.savedKeyHint('${existing['id']}'),
          onPlay: _play,
          onSignedOut: widget.ctx.signOut,
        ),
      ),
    );
    if (result == null) return;
    ed.edit(() {
      if (result['_delete'] == true) {
        ed.providers.removeWhere((p) => p['id'] == result['id']);
        if (ed.voiceProvider == result['id']) ed.voiceProvider = 'device';
        return;
      }
      final i = ed.providers.indexWhere((p) => p['id'] == result['id']);
      if (i >= 0) {
        ed.providers[i] = result;
      } else {
        ed.providers.add(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    final cfg = ed.cfg!;
    final active = ed.voiceProvider;
    final callModels = ['', ...ed.models];

    return PinnedPage(
      title: 'Voice',
      sub: 'Calls and read-aloud in the app',
      children: [
        StoreWarning(editor: ed),
        const SizedBox(height: 12),
        AppCard(
          child: SwitchRow(
            icon: HeroIcons.speakerWave,
            accent: ed.voiceEnabled ? Accent.green : sc.onSurfaceVariant,
            title: 'Voice in the app',
            sub: ed.voiceEnabled
                ? 'On: users see the call button and can have replies read aloud.'
                : 'Off: no call button and no read-aloud. Set it up below, then turn it on.',
            value: ed.voiceEnabled,
            onChanged: (v) => ed.edit(() => ed.voiceEnabled = v),
          ),
        ),

        const SectionTitle('Who speaks'),
        AppCard(
          child: Column(
            children: [
              _radio(
                context,
                selected: active == 'device',
                title: 'Phone voice',
                sub:
                    'Each phone\'s own Google Bangla voice. Free, nothing to set up.',
                onTap: () => ed.edit(() => ed.voiceProvider = 'device'),
              ),
              for (final p in ed.providers)
                Builder(
                  builder: (context) {
                    final gap = _missing(p);
                    return _radio(
                      context,
                      selected: active == p['id'],
                      title: '${p['name'] ?? p['type']}',
                      sub: [
                        _type('${p['type']}')?.label ?? '${p['type']}',
                        if ('${p['voice'] ?? ''}'.isNotEmpty) '${p['voice']}',
                        if (gap.isNotEmpty) 'needs $gap',
                      ].join(' · '),
                      warn: gap.isNotEmpty,
                      onTap: () {
                        if (gap.isNotEmpty) {
                          showSnack(context, 'Add the $gap first.');
                          return;
                        }
                        ed.edit(() => ed.voiceProvider = '${p['id']}');
                      },
                      trailing: IconButton(
                        tooltip: 'Edit ${p['name']}',
                        onPressed: () => _editProvider(p),
                        icon: const HeroIcon(HeroIcons.pencilSquare),
                      ),
                    );
                  },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlineButton(
                    label: 'Add a voice provider',
                    icon: HeroIcons.plus,
                    onPressed: () => _editProvider(null),
                  ),
                ),
              ),
            ],
          ),
        ),
        Note(
          _types.isEmpty
              ? (_typesError ?? 'Loading the providers...')
              : 'Available: ${_types.map((e) => e.label).join(', ')}. '
                    'Keys stay on the server; the app never sees them. '
                    'Cloud voices are paid services with their own free limits.',
        ),

        const SectionTitle('Phone voice'),
        AppCard(
          child: Column(
            children: [
              SettingRow(
                icon: HeroIcons.devicePhoneMobile,
                accent: Accent.teal,
                title: 'Voice',
                sub: ed.voiceName.isEmpty
                    ? 'Best Bangla voice on each phone'
                    : ed.voiceName,
                onTap: _pickPhoneVoice,
              ),
              LabeledSlider(
                title: 'Speed',
                value: ed.speed,
                min: 0.5,
                max: 2.0,
                divisions: 30,
                format: (v) => '${v.toStringAsFixed(2)}x',
                onChanged: (v) => ed.edit(() => ed.speed = v),
              ),
              LabeledSlider(
                title: 'Pitch',
                value: ed.pitch,
                min: 0.5,
                max: 2.0,
                divisions: 30,
                format: (v) => v.toStringAsFixed(2),
                onChanged: (v) => ed.edit(() => ed.pitch = v),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlineButton(
                    label: 'Hear it on this phone',
                    icon: HeroIcons.play,
                    onPressed: _hearPhone,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Note(
          'Speed and pitch apply to cloud voices too, where the provider supports them.',
        ),

        const SectionTitle('Call speed'),
        const Note(
          'A call turn waits for the user to stop talking, then for the AI\'s reply, then for the voice. '
          'These settings trim each wait.',
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingRow(
                icon: HeroIcons.bolt,
                accent: Accent.amber,
                title: 'Model for calls',
                sub: ed.callModel.isEmpty
                    ? 'Automatic: ${cfg.callModelInUse.isEmpty ? 'fastest listed' : cfg.callModelInUse}'
                    : ed.callModel,
                onTap: () async {
                  final picked = await showChoiceSheet<String>(
                    context,
                    title: 'Model for calls',
                    selected: ed.callModel,
                    options: [
                      for (final m in callModels)
                        ChoiceOption(
                          m,
                          m.isEmpty ? 'Automatic' : m,
                          sub: m.isEmpty
                              ? 'auto/fast when it is in your list, else the default model'
                              : null,
                        ),
                    ],
                  );
                  if (picked != null) ed.edit(() => ed.callModel = picked);
                },
              ),
              LabeledSlider(
                title: 'Reply length in calls',
                sub: 'Shorter replies arrive and finish sooner.',
                value: ed.callMaxTokens.toDouble(),
                min: 60,
                max: 400,
                divisions: 34,
                format: (v) => '${v.round()} tokens',
                onChanged: (v) => ed.edit(() => ed.callMaxTokens = v.round()),
              ),
              LabeledSlider(
                title: 'Pause that ends a turn',
                sub: 'How long the user is quiet before the AI answers.',
                value: ed.callPauseMs.toDouble(),
                min: 500,
                max: 2000,
                divisions: 15,
                format: (v) => '${(v / 1000).toStringAsFixed(1)} s',
                onChanged: (v) => ed.edit(() => ed.callPauseMs = v.round()),
              ),
              LabeledSlider(
                title: 'Conversation sent each turn',
                sub: 'Fewer messages make each turn a little faster.',
                value: ed.callHistory.toDouble(),
                min: 2,
                max: 30,
                divisions: 28,
                format: (v) => '${v.round()} messages',
                onChanged: (v) => ed.edit(() => ed.callHistory = v.round()),
              ),
              SwitchRow(
                icon: HeroIcons.cpuChip,
                accent: Accent.teal,
                title: 'Offline phone voice in calls',
                sub:
                    'Uses the offline twin of a network voice when the phone has it, so speech starts sooner.',
                value: ed.callOfflineVoice,
                onChanged: (v) => ed.edit(() => ed.callOfflineVoice = v),
              ),
            ],
          ),
        ),

        const SectionTitle('Cloud voice limit'),
        AppCard(
          child: LabeledSlider(
            title: 'Characters per day, all users',
            sub:
                'Protects a paid voice quota. When it is used up, phones fall back to their own voice.',
            value: ed.ttsDailyChars.toDouble().clamp(0, 2000000),
            min: 0,
            max: 2000000,
            divisions: 40,
            format: (v) => v == 0 ? 'No limit' : '${(v / 1000).round()}k',
            onChanged: (v) => ed.edit(() => ed.ttsDailyChars = v.round()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Text(
            'Phones pick up these settings the next time the app opens or comes back to the front.',
            style: t.bodySmall?.copyWith(color: sc.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _radio(
    BuildContext context, {
    required bool selected,
    required String title,
    required String sub,
    required VoidCallback onTap,
    bool warn = false,
    Widget? trailing,
  }) {
    final sc = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: HeroIcon(
        selected ? HeroIcons.checkCircle : HeroIcons.stop,
        color: selected ? sc.primary : sc.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(sub, style: TextStyle(color: warn ? sc.error : null)),
      trailing: trailing,
      selected: selected,
    );
  }
}

/// Adds or edits one cloud voice. The form comes from the server's list of
/// fields for that provider. Returns the provider map (or {'_delete': true}).
class ProviderEditor extends StatefulWidget {
  const ProviderEditor({
    super.key,
    required this.api,
    required this.type,
    required this.initial,
    required this.savedKeyHint,
    required this.onPlay,
    required this.onSignedOut,
  });

  final AdminApi api;
  final VoiceType type;
  final Map<String, dynamic>? initial;
  final String savedKeyHint;
  final Future<void> Function(VoiceSample) onPlay;
  final Future<void> Function() onSignedOut;

  @override
  State<ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends State<ProviderEditor> {
  late final String _id =
      '${widget.initial?['id'] ?? '${widget.type.type}-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'}';
  late final _name = TextEditingController(
    text: '${widget.initial?['name'] ?? widget.type.label}',
  );
  late final Map<String, TextEditingController> _c = {
    for (final f in widget.type.fields)
      f.key: TextEditingController(
        text: f.secret
            ? '${widget.initial?[f.key] ?? ''}'
            : '${widget.initial?[f.key] ?? (f.url ? f.hint : '')}',
      ),
  };
  bool _clearKey = false;
  bool _testing = false;
  VoiceSample? _result;

  @override
  void dispose() {
    _name.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _value() => {
    'id': _id,
    'type': widget.type.type,
    'name': _name.text.trim().isEmpty ? widget.type.label : _name.text.trim(),
    for (final f in widget.type.fields) f.key: _c[f.key]!.text.trim(),
    if (_clearKey) 'clearApiKey': true,
  };

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final r = await widget.api.voiceSample(_value());
      if (!mounted) return;
      setState(() => _result = r);
      if (r.ok) await widget.onPlay(r);
    } on ApiException catch (e) {
      if (e.signedOut) return widget.onSignedOut();
      if (mounted) {
        setState(() => _result = VoiceSample(ok: false, error: e.message));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    final type = widget.type;
    return Scaffold(
      body: PinnedPage(
        title: widget.initial == null
            ? 'Add ${type.label}'
            : '${widget.initial!['name']}',
        sub: type.label,
        onBack: () => Navigator.of(context).pop(),
        children: [
          if (type.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Note(type.note),
          ],
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                Field(_name, 'Name', helper: 'Only you see this.'),
                for (final f in type.fields) ...[
                  Field(
                    _c[f.key]!,
                    f.required ? f.label : '${f.label} (optional)',
                    hint:
                        f.secret && widget.savedKeyHint.isNotEmpty && !_clearKey
                        ? 'Saved ${widget.savedKeyHint}'
                        : f.hint,
                    helper: f.secret
                        ? (widget.savedKeyHint.isNotEmpty && !_clearKey
                              ? 'Saved key ends in ${widget.savedKeyHint.replaceAll('•', '')}. Leave empty to keep it.'
                              : 'Stored on the server only.')
                        : null,
                    obscure: f.secret,
                    type: f.url ? TextInputType.url : null,
                  ),
                  if (f.suggestions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in f.suggestions)
                            ChipButton(
                              label: s,
                              selected: _c[f.key]!.text == s,
                              onPressed: () =>
                                  setState(() => _c[f.key]!.text = s),
                            ),
                        ],
                      ),
                    ),
                  if (f.secret && widget.savedKeyHint.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _clearKey = !_clearKey),
                          child: Text(
                            _clearKey
                                ? 'Keep the saved key'
                                : 'Remove the saved key',
                          ),
                        ),
                      ),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlineButton(
                        label: _testing
                            ? 'Asking the server...'
                            : 'Hear a sample',
                        icon: HeroIcons.play,
                        onPressed: _testing ? null : _test,
                      ),
                      if (_result != null)
                        Text(
                          _result!.ok
                              ? 'Works (${(_result!.ms / 1000).toStringAsFixed(1)} s)'
                              : _result!.error,
                          style: t.bodyMedium?.copyWith(
                            color: _result!.ok ? Accent.green : sc.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: PrimaryButton(
              label: widget.initial == null ? 'Add' : 'Done',
              icon: HeroIcons.check,
              expand: true,
              onPressed: () => Navigator.of(context).pop(_value()),
            ),
          ),
          if (widget.initial != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: OutlineButton(
                label: 'Remove this provider',
                icon: HeroIcons.trash,
                expand: true,
                color: sc.error,
                onPressed: () =>
                    Navigator.of(context).pop({'id': _id, '_delete': true}),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Text(
              'Changes here wait for "Save for all users" on the Voice tab.',
              style: t.bodySmall?.copyWith(color: sc.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
