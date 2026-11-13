import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../state/editor.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/form_bits.dart';
import 'dashboard_screen.dart';

/// The AI tab: the OmniRoute connection, the models, and how the AI talks.
class AiPage extends StatefulWidget {
  const AiPage({super.key, required this.ctx});
  final AdminContext ctx;

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final _newModel = TextEditingController();
  final _try = TextEditingController(text: 'আজকে মনটা একটু খারাপ। কি করি?');
  bool _hideKey = true;
  bool _testing = false;
  TestResult? _test;
  bool _trying = false;
  bool _tryCall = false;
  TestResult? _tried;

  @override
  void dispose() {
    _newModel.dispose();
    _try.dispose();
    super.dispose();
  }

  Editor get ed => widget.ctx.editor;

  Future<void> _runTest() async {
    final problem = ed.problem();
    if (problem != null) return showSnack(context, problem);
    setState(() {
      _testing = true;
      _test = null;
    });
    try {
      final r = await widget.ctx.api.test({
        ...ed.patch(),
        'model': ed.defaultModel,
      });
      if (mounted) setState(() => _test = r);
    } on ApiException catch (e) {
      if (e.signedOut) return widget.ctx.signOut();
      if (mounted) {
        setState(() => _test = TestResult(ok: false, error: e.message));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _runTry() async {
    final text = _try.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _trying = true;
      _tried = null;
    });
    try {
      final d = Map<String, dynamic>.from(ed.patch())..remove('voiceProviders');
      final r = await widget.ctx.api.tryChat(text, call: _tryCall, draft: d);
      if (mounted) setState(() => _tried = r);
    } on ApiException catch (e) {
      if (e.signedOut) return widget.ctx.signOut();
      if (mounted) {
        setState(() => _tried = TestResult(ok: false, error: e.message));
      }
    } finally {
      if (mounted) setState(() => _trying = false);
    }
  }

  Future<void> _resetStyles() async {
    try {
      final (style, call) = await widget.ctx.api.defaults();
      ed.stylePrompt.text = style;
      ed.callPrompt.text = call;
      if (mounted) {
        showSnack(context, 'Starting styles put back. Save to use them.');
      }
    } on ApiException catch (e) {
      if (e.signedOut) return widget.ctx.signOut();
      if (mounted) showSnack(context, e.message);
    }
  }

  void _addModel() {
    final m = _newModel.text.trim();
    if (m.isEmpty) return;
    if (ed.models.contains(m)) {
      return showSnack(context, '$m is already in the list.');
    }
    ed.edit(() => ed.models.add(m));
    _newModel.clear();
  }

  void _removeModel(String m) {
    if (ed.models.length == 1) {
      return showSnack(context, 'Keep at least one model.');
    }
    ed.edit(() {
      ed.models.remove(m);
      if (ed.defaultModel == m) ed.defaultModel = ed.models.first;
      if (ed.callModel == m) ed.callModel = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    final cfg = ed.cfg!;
    return PinnedPage(
      title: 'AI',
      sub: 'Connection, models and how the AI talks',
      children: [
        StoreWarning(editor: ed),
        const SectionTitle('AI connection (OmniRoute)', top: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Field(
                ed.baseUrl,
                'Base URL',
                hint: 'https://your-omniroute.example.com/v1',
                helper: 'The OpenAI-compatible address, usually ending in /v1.',
                type: TextInputType.url,
              ),
              Field(
                ed.apiKey,
                'API key',
                hint: cfg.apiKeySet ? 'Saved ${cfg.apiKeyHint}' : 'sk-...',
                helper: cfg.apiKeySet
                    ? 'Saved key ends in ${cfg.apiKeyHint.replaceAll('•', '')}. Leave empty to keep it.'
                    : 'No key saved yet.',
                obscure: _hideKey,
                suffix: IconButton(
                  tooltip: _hideKey ? 'Show key' : 'Hide key',
                  onPressed: () => setState(() => _hideKey = !_hideKey),
                  icon: HeroIcon(
                    _hideKey ? HeroIcons.eye : HeroIcons.eyeSlash,
                    size: 20,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlineButton(
                      label: _testing ? 'Testing...' : 'Test connection',
                      onPressed: _testing ? null : _runTest,
                    ),
                    if (_test != null)
                      Text(
                        _test!.ok
                            ? 'Works (${(_test!.ms / 1000).toStringAsFixed(1)} s): "${_test!.reply}"'
                            : _test!.error,
                        style: t.bodyMedium?.copyWith(
                          color: _test!.ok ? Accent.green : sc.error,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SectionTitle('Models'),
        const Note(
          'Users pick from these. The ticked one is the default for text chats.',
        ),
        AppCard(
          child: Column(
            children: [
              for (final m in ed.models)
                ListTile(
                  leading: IconButton(
                    tooltip: m == ed.defaultModel ? 'Default' : 'Make default',
                    onPressed: () => ed.edit(() => ed.defaultModel = m),
                    icon: HeroIcon(
                      m == ed.defaultModel
                          ? HeroIcons.checkCircle
                          : HeroIcons.sparkles,
                      color: m == ed.defaultModel
                          ? sc.primary
                          : sc.onSurfaceVariant,
                    ),
                  ),
                  title: Text(m, style: t.titleMedium),
                  subtitle: Text(
                    [
                      if (m == ed.defaultModel) 'Default',
                      if (m ==
                          (ed.callModel.isEmpty
                              ? cfg.callModelInUse
                              : ed.callModel))
                        'Used in calls',
                    ].join(' · '),
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove $m',
                    onPressed: () => _removeModel(m),
                    icon: const HeroIcon(HeroIcons.trash),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newModel,
                        autocorrect: false,
                        onSubmitted: (_) => _addModel(),
                        decoration: const InputDecoration(
                          labelText: 'Add a model',
                          hintText: 'e.g. auto/fast',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add',
                      onPressed: _addModel,
                      icon: HeroIcon(HeroIcons.plus, color: sc.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SectionTitle('How the AI talks'),
        const Note(
          'Sent before every chat, in this order: your instructions, the conversation style, '
          'then (in calls only) the call style. The app adds which language to reply in.',
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Field(
                ed.systemPrompt,
                'Your instructions',
                hint:
                    'e.g. You are a friendly assistant for Bangladeshi users.',
                helper:
                    'What the AI is for: topics, rules, facts about your service.',
                maxLines: 6,
              ),
              Field(
                ed.stylePrompt,
                'Conversation style',
                helper:
                    'The tone: laid-back, sharp and warm, no flattery or canned lines, '
                    'natural spoken Bangla.',
                maxLines: 8,
              ),
              Field(
                ed.callPrompt,
                'Call style',
                helper:
                    'Extra rules for voice calls: short spoken sentences, no lists.',
                maxLines: 5,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _resetStyles,
                    icon: const HeroIcon(HeroIcons.arrowUturnLeft, size: 18),
                    label: const Text('Put back the starting styles'),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SectionTitle('Try it'),
        const Note(
          'Ask something and see the reply with the settings above, before you save.',
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Field(_try, 'Message', maxLines: 3),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChipButton(
                      label: 'Text chat',
                      selected: !_tryCall,
                      onPressed: () => setState(() => _tryCall = false),
                    ),
                    ChipButton(
                      label: 'Voice call',
                      selected: _tryCall,
                      onPressed: () => setState(() => _tryCall = true),
                    ),
                    PrimaryButton(
                      label: _trying ? 'Asking...' : 'Ask',
                      icon: HeroIcons.chatBubbleLeftRight,
                      onPressed: _trying ? null : _runTry,
                    ),
                  ],
                ),
              ),
              if (_tried != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: _tried!.ok
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(_tried!.reply, style: t.bodyLarge),
                            const SizedBox(height: 6),
                            Text(
                              '${(_tried!.ms / 1000).toStringAsFixed(1)} s for the whole reply',
                              style: t.bodySmall?.copyWith(
                                color: sc.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          _tried!.error,
                          style: t.bodyMedium?.copyWith(color: sc.error),
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
