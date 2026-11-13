import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/form_bits.dart';
import 'dashboard_screen.dart';

/// The home tab: how the app is doing, in numbers. Everything comes from the
/// server's daily counters (no message text, no IP addresses).
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key, required this.ctx});
  final AdminContext ctx;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

enum _Period { today, week, month }

class _OverviewPageState extends State<OverviewPage> {
  Stats? _stats;
  String? _error;
  bool _loading = true;
  _Period _period = _Period.week;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.ctx.api.stats(days: 30);
      if (mounted) setState(() => _stats = s);
    } on ApiException catch (e) {
      if (e.signedOut) return widget.ctx.signOut();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String n(num? v) {
    if (v == null) return '0';
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String secs(num? ms) =>
      ms == null ? '–' : '${(ms / 1000).toStringAsFixed(1)} s';

  static String uptime(int s) {
    if (s < 3600) return '${(s / 60).floor()} min';
    if (s < 86400) return '${(s / 3600).toStringAsFixed(1)} h';
    return '${(s / 86400).toStringAsFixed(1)} days';
  }

  String get _periodKey => switch (_period) {
    _Period.today => 'today',
    _Period.week => 'week',
    _Period.month => 'month',
  };

  String get _periodName => switch (_period) {
    _Period.today => 'today',
    _Period.week => 'in the last 7 days',
    _Period.month => 'in the last 30 days',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    final ed = widget.ctx.editor;
    final cfg = ed.cfg!;
    final s = _stats;

    final children = <Widget>[
      StoreWarning(editor: ed),
      const SizedBox(height: 8),
      _StatusCard(
        items: [
          _Status(
            'App',
            cfg.enabled ? 'On' : 'Off',
            cfg.enabled,
            onTap: () => widget.ctx.goTo(3),
          ),
          _Status(
            'AI connection',
            (s?.server['ready'] ?? (cfg.baseUrl.isNotEmpty && cfg.apiKeySet)) ==
                    true
                ? 'Set up'
                : 'Not set up',
            (s?.server['ready'] ?? (cfg.baseUrl.isNotEmpty && cfg.apiKeySet)) ==
                true,
            onTap: () => widget.ctx.goTo(1),
          ),
          _Status(
            'Voice',
            !cfg.voiceEnabled
                ? 'Off'
                : cfg.voiceProvider == 'device'
                ? 'Phone voice'
                : 'Cloud voice',
            cfg.voiceEnabled,
            neutral: !cfg.voiceEnabled,
            onTap: () => widget.ctx.goTo(2),
          ),
          if (s != null)
            _Status(
              'Database',
              s.server['storeOk'] == true ? 'OK' : 'Down',
              s.server['storeOk'] == true,
            ),
          if (s != null)
            _Status(
              'Sign-in email',
              s.server['emailReady'] == true ? 'OK' : 'Not set up',
              s.server['emailReady'] == true,
            ),
        ],
      ),
      const SizedBox(height: 14),
      ChipRow(
        children: [
          for (final (p, label) in [
            (_Period.today, 'Today'),
            (_Period.week, '7 days'),
            (_Period.month, '30 days'),
          ])
            ChipButton(
              label: label,
              selected: _period == p,
              onPressed: () => setState(() => _period = p),
            ),
        ],
      ),
    ];

    if (s == null) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      Text(
                        _error ?? 'No numbers yet.',
                        textAlign: TextAlign.center,
                        style: t.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      OutlineButton(label: 'Try again', onPressed: _load),
                    ],
                  ),
          ),
        ),
      );
    } else {
      final p = s.period(_periodKey);
      final messages = (p['messages'] as num?) ?? 0;
      final failures = (p['failures'] as num?) ?? 0;
      final failRate = messages + (p['tts'] as num? ?? 0) == 0
          ? null
          : failures * 100 / (messages + (p['tts'] as num? ?? 0));
      final days = _period == _Period.month ? 30 : 7;
      final series = s.series.length > days
          ? s.series.sublist(s.series.length - days)
          : s.series;
      String short(String day) {
        final d = DateTime.tryParse(day);
        if (d == null) return day;
        const m = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        return '${d.day} ${m[d.month - 1]}';
      }

      Map<String, num> map(Object? o) => {
        for (final e in ((o as Map?) ?? const {}).entries)
          '${e.key}': (e.value as num?) ?? 0,
      };
      final voices = map(p['voices']).map((k, v) {
        final i = k.indexOf(':');
        return MapEntry(i < 0 ? k : k.substring(i + 1), v);
      });

      children.addAll([
        const SizedBox(height: 12),
        MetricGrid(
          children: [
            MetricTile(
              label: 'Messages',
              value: n(messages),
              sub: _periodName,
              icon: HeroIcons.chatBubbleLeftRight,
              accent: Accent.green,
            ),
            MetricTile(
              label: 'Active phones',
              value: n(p['activeDevices'] as num?),
              sub:
                  '${n(p['newDevices'] as num?)} new · ${n(s.totalDevices)} total',
              icon: HeroIcons.devicePhoneMobile,
              accent: Accent.teal,
            ),
            MetricTile(
              label: 'Text chats',
              value: n(p['chats'] as num?),
              sub: 'replies asked for',
              icon: HeroIcons.chatBubbleOvalLeft,
              accent: sc.primary,
            ),
            MetricTile(
              label: 'Voice call turns',
              value: n(p['callTurns'] as num?),
              sub: cfg.voiceEnabled ? 'replies in calls' : 'voice is off',
              icon: HeroIcons.phone,
              accent: Accent.amber,
            ),
            MetricTile(
              label: 'Reply starts in',
              value: secs(p['chatReplyMs'] as num?),
              sub: 'text chat, average',
              icon: HeroIcons.clock,
              accent: sc.primary,
            ),
            MetricTile(
              label: 'Call reply starts in',
              value: secs(p['callReplyMs'] as num?),
              sub: 'voice calls, average',
              icon: HeroIcons.bolt,
              accent: Accent.amber,
            ),
            MetricTile(
              label: 'Errors',
              value: n(failures),
              sub: failRate == null
                  ? 'no requests'
                  : '${failRate.toStringAsFixed(1)}% of requests',
              icon: HeroIcons.exclamationTriangle,
              accent: failures > 0 ? Accent.red : Accent.green,
            ),
            MetricTile(
              label: 'Cloud voice clips',
              value: n(p['tts'] as num?),
              sub:
                  '${n(p['ttsChars'] as num?)} characters · ${secs(p['ttsMs'] as num?)}',
              icon: HeroIcons.speakerWave,
              accent: Accent.teal,
            ),
          ],
        ),
        SectionTitle(
          _period == _Period.month
              ? 'Messages, last 30 days'
              : 'Messages, last 7 days',
        ),
        AppCard(
          child: BarChart(
            labels: [for (final d in series) short('${d['day']}')],
            series: [
              BarSeries('Text chats', sc.primary, [
                for (final d in series) (d['chats'] as num?) ?? 0,
              ]),
              BarSeries('Call turns', Accent.amber, [
                for (final d in series) (d['callTurns'] as num?) ?? 0,
              ]),
              BarSeries('Errors', Accent.red, [
                for (final d in series) (d['failures'] as num?) ?? 0,
              ]),
            ],
          ),
        ),
        const SectionTitle('Active phones per day'),
        AppCard(
          child: BarChart(
            height: 110,
            labels: [for (final d in series) short('${d['day']}')],
            series: [
              BarSeries('Phones', Accent.teal, [
                for (final d in series) (d['devices'] as num?) ?? 0,
              ]),
            ],
          ),
        ),
        const SectionTitle('Requests per model'),
        AppCard(
          child: ShareList(
            items: map(p['models']),
            color: sc.primary,
            empty: 'No chats $_periodName.',
          ),
        ),
        const SectionTitle('Cloud voice use'),
        AppCard(
          child: ShareList(
            items: voices,
            color: Accent.teal,
            empty: cfg.voiceEnabled
                ? (cfg.voiceProvider == 'device'
                      ? 'Phones use their own voice, so the server sends no audio.'
                      : 'No voice clips $_periodName.')
                : 'Voice is off. Turn it on in the Voice tab when you are ready.',
          ),
        ),
        const SectionTitle('Errors'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShareList(
                items: map(p['errorKinds']),
                color: Accent.red,
                empty: 'No errors $_periodName.',
              ),
              if (s.recentErrors.isNotEmpty) ...[
                Divider(color: sc.outlineVariant, height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Latest', style: t.titleSmall),
                ),
                for (final e in s.recentErrors.take(6))
                  ListTile(
                    dense: true,
                    title: Text(
                      '${e['message']}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${e['where']} · ${DateTime.tryParse('${e['at']}')?.toLocal().toString().substring(0, 16) ?? ''}',
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        const SectionTitle('Right now'),
        AppCard(
          child: Column(
            children: [
              _row(
                context,
                'Reply start, last 50 chats',
                secs(s.recent['chatReplyMs'] as num?),
              ),
              _row(
                context,
                'Reply start, last 50 call turns',
                secs(s.recent['callReplyMs'] as num?),
              ),
              _row(
                context,
                'Voice clip, last 50',
                secs(s.recent['ttsMs'] as num?),
              ),
              _row(context, 'Server up for', uptime(s.uptimeSeconds)),
              _row(context, 'Server version', '${s.server['version'] ?? ''}'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(
            'Counted by the server since ${s.since}, by day in ${s.timezone} time. '
            'A phone is counted by a random app install id, stored only as a scrambled code. '
            'No message text or IP address is kept.',
            style: t.bodySmall?.copyWith(color: sc.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 24),
      ]);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: PinnedPage(
        title: 'Overview',
        sub: widget.ctx.host,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const HeroIcon(HeroIcons.arrowPath),
          ),
        ],
        children: children,
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: t.bodyMedium)),
          Text(value, style: t.titleSmall),
        ],
      ),
    );
  }
}

class _Status {
  const _Status(
    this.label,
    this.value,
    this.good, {
    this.neutral = false,
    this.onTap,
  });
  final String label;
  final String value;
  final bool good;
  final bool neutral;
  final VoidCallback? onTap;
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.items});
  final List<_Status> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sc = Theme.of(context).colorScheme;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in items)
              InkWell(
                borderRadius: BorderRadius.circular(Radii.pill),
                onTap: s.onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: Border.all(color: sc.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: s.neutral
                              ? sc.onSurfaceVariant
                              : s.good
                              ? Accent.green
                              : Accent.red,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${s.label}: ',
                        style: t.bodySmall?.copyWith(
                          color: sc.onSurfaceVariant,
                        ),
                      ),
                      Text(s.value, style: t.labelLarge),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
