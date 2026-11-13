import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight.dart' show highlight, Node;
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import 'components.dart';

/// Renders an AI reply: GitHub-flavoured Markdown with code blocks that
/// have a language label, syntax colours and a copy button.
///
/// While a reply streams in ([live]), the text is cut into the blocks that
/// are already finished and the one still growing. Each finished block is
/// its own Markdown widget whose text no longer changes, so it is parsed
/// once; only the growing tail is parsed again as chunks arrive. Long
/// replies stay smooth instead of re-parsing everything on every chunk.
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.data,
    this.selectable = true,
    this.live = false,
  });
  final String data;
  final bool selectable;

  /// The reply is still streaming: a cursor dot follows the text.
  final bool live;

  static const _cursor = ' \u25CF';
  static const _blockSpacing = 12.0;
  static final _sheets = Expando<MarkdownStyleSheet>('markdown sheet');
  static final Map<String, MarkdownElementBuilder> _builders = {
    'pre': _CodeBlockBuilder(),
  };

  @override
  Widget build(BuildContext context) {
    final sheet = _sheetFor(context);
    if (!live) return _body(context, data, sheet, selectable);
    final blocks = splitSettledBlocks(data);
    if (blocks.length == 1) {
      return _body(context, '${blocks.first}$_cursor', sheet, false);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: _blockSpacing),
          KeyedSubtree(
            key: ValueKey<int>(i),
            child: _body(
              context,
              i == blocks.length - 1 ? '${blocks[i]}$_cursor' : blocks[i],
              sheet,
              false,
            ),
          ),
        ],
      ],
    );
  }

  Widget _body(
    BuildContext context,
    String text,
    MarkdownStyleSheet sheet,
    bool selectable,
  ) {
    return MarkdownBody(
      data: text,
      selectable: selectable,
      styleSheet: sheet,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: _builders,
      imageBuilder: (uri, title, alt) => _MarkdownImage(uri: uri, alt: alt),
      onTapLink: (text, href, title) async {
        final uri = href == null ? null : Uri.tryParse(href);
        if (uri == null) return;
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
            context.mounted) {
          showSnack(context, context.l10n.couldNotOpen('$href'));
        }
      },
    );
  }

  /// One style sheet per theme, made once, so rebuilds do not rebuild it.
  static MarkdownStyleSheet _sheetFor(BuildContext context) {
    final theme = Theme.of(context);
    return _sheets[theme] ??= _makeSheet(context, theme);
  }

  static MarkdownStyleSheet _makeSheet(BuildContext context, ThemeData theme) {
    final s = theme.colorScheme;
    final t = theme.textTheme;
    final dark = AppColors.of(context).dark;
    final body = t.bodyLarge!.copyWith(color: s.onSurface);
    return MarkdownStyleSheet(
      p: body,
      pPadding: EdgeInsets.zero,
      a: body.copyWith(
        color: dark ? Palette.green : Palette.link,
        decoration: TextDecoration.underline,
        decorationColor: dark ? Palette.green : Palette.link,
      ),
      strong: const TextStyle(
        fontWeight: FontWeight.w700,
        fontVariations: [FontVariation.weight(700)],
      ),
      em: const TextStyle(fontStyle: FontStyle.italic),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      h1: t.headlineSmall,
      h2: t.titleLarge,
      h3: t.titleMedium,
      h4: t.titleSmall,
      h5: t.titleSmall,
      h6: t.titleSmall,
      h1Padding: const EdgeInsets.only(top: 8),
      h2Padding: const EdgeInsets.only(top: 6),
      h3Padding: const EdgeInsets.only(top: 4),
      code: AppText.code.copyWith(
        color: s.onSurface,
        backgroundColor: s.surfaceContainerHigh,
        fontSize: 14,
      ),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(),
      blockquote: body.copyWith(color: s.onSurfaceVariant),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: s.primary, width: 3)),
      ),
      listBullet: body,
      listIndent: 22,
      blockSpacing: _blockSpacing,
      tableHead: t.titleSmall,
      tableBody: t.bodyMedium,
      tableBorder: TableBorder.all(color: s.outlineVariant),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      // Intrinsic widths make wide tables scroll sideways instead of
      // squeezing or overflowing on narrow phones.
      tableColumnWidth: const IntrinsicColumnWidth(),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: s.outlineVariant)),
      ),
      checkbox: body.copyWith(color: s.primary),
    );
  }
}

/// Splits streaming Markdown into finished top-level blocks and the tail
/// that is still growing. A block ends at a blank line outside a code
/// fence when the next line clearly starts a new block (not an indented
/// line, a list item or a table row, which could continue the block above).
/// Joining the parts with blank lines gives the same document back.
List<String> splitSettledBlocks(String text) {
  final lines = text.split('\n');
  final blocks = <String>[];
  var start = 0;
  String? fence;
  final listItem = RegExp(r'^\s*([-*+]|\d{1,9}[.)])(\s|$)');
  final fenceOpen = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final f = fenceOpen.firstMatch(line);
    if (fence != null) {
      if (f != null && f.group(1)!.startsWith(fence)) fence = null;
      continue;
    }
    if (f != null) {
      fence = f.group(1)![0] * 3;
      continue;
    }
    if (line.trim().isNotEmpty) continue;
    // A blank line: find the next line with text.
    var j = i + 1;
    while (j < lines.length && lines[j].trim().isEmpty) {
      j++;
    }
    if (j >= lines.length) break; // Nothing after it yet: still the tail.
    final next = lines[j];
    final prev = lines.sublist(start, i).join('\n');
    final continues =
        next.startsWith(' ') ||
        next.startsWith('\t') ||
        listItem.hasMatch(next) ||
        next.trimLeft().startsWith('|') ||
        next.trimLeft().startsWith('[');
    if (prev.trim().isNotEmpty && !continues) {
      blocks.add(prev);
      start = j;
      i = j - 1;
    }
  }
  final tail = lines.sublist(start).join('\n');
  if (tail.trim().isNotEmpty || blocks.isEmpty) blocks.add(tail);
  return blocks;
}

/// An image in a reply: fits the width, decodes at screen size, fades in,
/// and keeps a fixed placeholder height while it loads so the chat does not
/// jump.
class _MarkdownImage extends StatelessWidget {
  const _MarkdownImage({required this.uri, this.alt});
  final Uri uri;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      return Text(alt ?? '', style: TextStyle(color: s.onSurfaceVariant));
    }
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.isFinite ? box.maxWidth : 400.0;
        final px = (width * MediaQuery.devicePixelRatioOf(context)).round();
        return ClipRRect(
          borderRadius: BorderRadius.circular(Radii.tile),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: 420),
            child: Image.network(
              uri.toString(),
              cacheWidth: px,
              fit: BoxFit.contain,
              semanticLabel: alt,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, sync) {
                if (sync) return child;
                return AnimatedSwitcher(
                  duration: Motion.fade,
                  child: frame == null
                      ? Container(
                          key: const ValueKey('wait'),
                          width: width,
                          height: 180,
                          color: s.surfaceContainerHigh,
                        )
                      : child,
                );
              },
              errorBuilder: (context, error, stack) => Container(
                padding: const EdgeInsets.all(12),
                color: s.surfaceContainerHigh,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HeroIcon(
                      HeroIcons.exclamationTriangle,
                      size: 18,
                      color: s.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        alt?.isNotEmpty == true ? alt! : uri.host,
                        style: TextStyle(color: s.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var language = '';
    final code = element.children?.whereType<md.Element>().firstOrNull;
    final cls = code?.attributes['class'];
    if (cls != null && cls.startsWith('language-')) {
      language = cls.substring('language-'.length);
    }
    var text = element.textContent;
    if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
    return CodeBlock(code: text, language: language);
  }
}

/// A fenced code block: header with the language and Copy, then the code
/// in DM Mono, scrolling sideways when lines are long.
class CodeBlock extends StatefulWidget {
  const CodeBlock({super.key, required this.code, this.language = ''});
  final String code;
  final String language;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;

  // Highlighting is the slow part: done once per code, language and colours,
  // not on every rebuild.
  List<TextSpan>? _spans;
  String? _spansFor;

  List<TextSpan> _highlighted(CodeColors colors, bool dark) {
    final key =
        '${widget.language}|$dark|${colors.keyword.toARGB32()}|'
        '${colors.comment.toARGB32()}|${widget.code}';
    if (_spans == null || _spansFor != key) {
      _spans = highlightCode(widget.code, widget.language, colors);
      _spansFor = key;
    }
    return _spans!;
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final dark = AppColors.of(context).dark;
    final base = AppText.code.copyWith(color: s.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: dark ? s.surfaceContainerLowest : s.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Radii.tile),
          border: Border.all(color: s.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: s.surfaceContainerHigh,
              padding: const EdgeInsets.only(left: 14, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.language.isEmpty
                          ? context.l10n.code
                          : widget.language.toLowerCase(),
                      style: t.labelMedium?.copyWith(color: s.onSurfaceVariant),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _copy,
                    style: TextButton.styleFrom(
                      foregroundColor: s.onSurfaceVariant,
                      textStyle: t.labelMedium,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: HeroIcon(
                      _copied
                          ? HeroIcons.clipboardDocumentCheck
                          : HeroIcons.clipboardDocument,
                      size: 16,
                      color: _copied ? Palette.success : s.onSurfaceVariant,
                    ),
                    label: Text(
                      _copied ? context.l10n.copied : context.l10n.copy,
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: SelectableText.rich(
                TextSpan(
                  style: base,
                  children: _highlighted(CodeColors.of(s, dark), dark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Syntax colours, all taken from the palette.
class CodeColors {
  const CodeColors({
    required this.keyword,
    required this.string,
    required this.comment,
    required this.number,
    required this.title,
    required this.type,
  });

  final Color keyword, string, comment, number, title, type;

  static CodeColors of(ColorScheme s, bool dark) => CodeColors(
    keyword: dark ? Palette.green : Palette.greenDeep,
    string: Palette.success,
    comment: s.onSurfaceVariant,
    number: dark ? Accent.amber : Palette.warning,
    title: Palette.red,
    type: dark ? Palette.greenLight : Palette.link,
  );

  TextStyle? styleFor(String? cls) {
    switch (cls) {
      case 'keyword' || 'selector-tag' || 'literal' || 'meta' || 'doctag':
        return TextStyle(color: keyword);
      case 'string' || 'regexp' || 'addition' || 'attribute' || 'symbol':
        return TextStyle(color: string);
      case 'comment' || 'quote':
        return TextStyle(color: comment, fontStyle: FontStyle.italic);
      case 'number' || 'bullet' || 'link':
        return TextStyle(color: number);
      case 'title' || 'section' || 'name' || 'function' || 'selector-id':
        return TextStyle(color: title);
      case 'type' ||
          'built_in' ||
          'class' ||
          'params' ||
          'attr' ||
          'variable' ||
          'template-variable' ||
          'selector-class':
        return TextStyle(color: type);
      case 'deletion':
        return const TextStyle(color: Palette.error);
    }
    return null;
  }
}

/// Turns code into coloured spans. Unknown languages stay plain.
List<TextSpan> highlightCode(String code, String language, CodeColors c) {
  final lang = _aliases[language.toLowerCase()] ?? language.toLowerCase();
  try {
    final result = lang.isEmpty || code.length > 20000
        ? null
        : highlight.parse(code, language: lang);
    final nodes = result?.nodes;
    if (nodes == null) return [TextSpan(text: code)];
    List<TextSpan> walk(List<Node> list) => [
      for (final n in list)
        n.value != null
            ? TextSpan(text: n.value, style: c.styleFor(n.className))
            : TextSpan(
                style: c.styleFor(n.className),
                children: walk(n.children ?? const []),
              ),
    ];
    return walk(nodes);
  } catch (_) {
    return [TextSpan(text: code)];
  }
}

const _aliases = {
  'js': 'javascript',
  'ts': 'typescript',
  'py': 'python',
  'sh': 'bash',
  'shell': 'bash',
  'zsh': 'bash',
  'kt': 'kotlin',
  'yml': 'yaml',
  'c++': 'cpp',
  'cs': 'csharp',
  'c#': 'csharp',
  'html': 'xml',
  'jsx': 'javascript',
  'tsx': 'typescript',
  'rb': 'ruby',
  'rs': 'rust',
  'md': 'markdown',
};
