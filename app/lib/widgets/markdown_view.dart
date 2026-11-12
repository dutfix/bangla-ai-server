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
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data, this.selectable = true});
  final String data;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final t = theme.textTheme;
    final body = t.bodyLarge!.copyWith(color: s.onSurface);
    final sheet = MarkdownStyleSheet(
      p: body,
      pPadding: EdgeInsets.zero,
      a: body.copyWith(
        color: AppColors.of(context).dark ? Palette.green : Palette.link,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.of(context).dark
            ? Palette.green
            : Palette.link,
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
      blockSpacing: 12,
      tableHead: t.titleSmall,
      tableBody: t.bodyMedium,
      tableBorder: TableBorder.all(color: s.outlineVariant),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      tableColumnWidth: const IntrinsicColumnWidth(),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: s.outlineVariant)),
      ),
      checkbox: body.copyWith(color: s.primary),
    );
    return MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: sheet,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: {'pre': _CodeBlockBuilder()},
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
                  children: highlightCode(
                    widget.code,
                    widget.language,
                    CodeColors.of(s, dark),
                  ),
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
