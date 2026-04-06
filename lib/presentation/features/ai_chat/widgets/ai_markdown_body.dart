import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';
import 'package:flutter_highlighter/themes/atom-one-light.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/ai_message_markup.dart';

const Set<String> _safeMarkdownRootTags = <String>{
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'blockquote',
  'pre',
  'ol',
  'ul',
  'hr',
  'table',
  'thead',
  'tbody',
  'tr',
  'section',
};

bool _canRenderMarkdownSafely(String markdown) {
  try {
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    final nodes = document.parseLines(const LineSplitter().convert(markdown));
    return nodes.every((node) {
      if (node is! md.Element) {
        return false;
      }
      return _safeMarkdownRootTags.contains(node.tag);
    });
  } catch (_) {
    return false;
  }
}

/// 魔法代码块渲染引擎
class AIMessageMarkdown extends StatelessWidget {
  const AIMessageMarkdown({
    super.key,
    required this.content,
    this.isError = false,
    this.style,
    this.onRunCode,
    this.showThinkingByDefault = false,
    this.segments,
  });

  final String content;
  final bool isError;
  final TextStyle? style;
  final void Function(String)? onRunCode; // 核心：一键运行代码回调
  final bool showThinkingByDefault;
  final List<AIMessageSegment>? segments;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onSurface;

    final effectiveSegments = segments ?? parseAiMessageSegments(content);
    if (effectiveSegments.isEmpty) {
      return _buildMarkdownBody(context, content, textColor);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: effectiveSegments.map((segment) {
        switch (segment.type) {
          case AIMessageSegmentType.markdown:
            return _buildMarkdownBody(context, segment.content, textColor);
          case AIMessageSegmentType.thinking:
            return _ThinkingDisclosure(
              content: segment.content,
              style: style,
              initialExpanded: showThinkingByDefault,
            );
        }
      }).toList(growable: false),
    );
  }

  Widget _buildMarkdownBody(
    BuildContext context,
    String markdown,
    Color textColor,
  ) {
    final trimmed = markdown.trim();
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final paragraphStyle = style ??
        TextStyle(
          color: textColor,
          fontSize: 15,
          height: 1.6,
        );

    if (!_canRenderMarkdownSafely(markdown)) {
      return SelectableText(
        markdown.trimRight(),
        style: paragraphStyle,
      );
    }

    return MarkdownBody(
      data: markdown,
      selectable: true,
      shrinkWrap: true,
      builders: {
        'pre': _CodeBlockBuilder(
          context: context,
          onRunCode: onRunCode,
        ),
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        blockSpacing: 12,
        p: paragraphStyle,
        h1: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        h2: TextStyle(
          color: textColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        h3: TextStyle(
          color: textColor,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        code: TextStyle(
          fontFamily: 'JetBrainsMono',
          backgroundColor:
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          color: colorScheme.primary,
          fontSize: 13.5,
        ),
        blockquote: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
          height: 1.5,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 4),
          ),
        ),
      ),
    );
  }
}

class _ThinkingDisclosure extends StatefulWidget {
  const _ThinkingDisclosure({
    required this.content,
    this.style,
    this.initialExpanded = false,
  });

  final String content;
  final TextStyle? style;
  final bool initialExpanded;

  @override
  State<_ThinkingDisclosure> createState() => _ThinkingDisclosureState();
}

class _ThinkingDisclosureState extends State<_ThinkingDisclosure> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final paragraphStyle = widget.style ??
        TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
          height: 1.6,
        );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_alt_outlined,
                    size: 16,
                    color: colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '模型思考',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    _expanded ? '收起' : '查看',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _canRenderMarkdownSafely(widget.content)
                  ? MarkdownBody(
                      data: widget.content,
                      selectable: true,
                      shrinkWrap: true,
                      styleSheet:
                          MarkdownStyleSheet.fromTheme(Theme.of(context))
                              .copyWith(
                        p: paragraphStyle,
                      ),
                    )
                  : SelectableText(
                      widget.content.trimRight(),
                      style: paragraphStyle,
                    ),
            ),
        ],
      ),
    );
  }
}

/// 复制文本并轻微震动
Future<void> copyChatText(
  BuildContext context,
  String text, {
  required String successMessage,
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return;

  await Clipboard.setData(ClipboardData(text: text));
  HapticFeedback.lightImpact();
  
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(successMessage), duration: const Duration(seconds: 1)));
}

/// 定制化高级代码块渲染器
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({required this.context, this.onRunCode});

  final BuildContext context;
  final void Function(String)? onRunCode;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = _extractText(element).trimRight();
    if (code.isEmpty) return const SizedBox.shrink();

    final language = _extractLanguage(element) ?? 'text';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 使用顶级极客高亮主题
    final theme = isDark ? atomOneDarkTheme : atomOneLightTheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: theme['root']?.backgroundColor ?? const Color(0xFF282C34),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 极客风卡片头部
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            child: Row(
              children: [
                Text(
                  language.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                ),
                const Spacer(),
                // 杀手锏：一键送入终端执行
                if (onRunCode != null)
                  TextButton.icon(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      onRunCode!(code);
                    },
                    icon: const Icon(Icons.play_arrow, size: 14, color: Color(0xFF10B981)),
                    label: const Text('注入终端', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => copyChatText(context, code, successMessage: '代码已复制'),
                  icon: Icon(Icons.copy, size: 14, color: Colors.grey.shade500),
                  label: Text('复制', style: TextStyle(color: Colors.grey.shade500)),
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          // 真正的语法高亮代码区
          SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: HighlightView(
                code,
                language: language,
                theme: theme,
                textStyle: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _extractText(md.Node node) {
    if (node is md.Text) return node.text;
    if (node is md.Element) {
      final children = node.children;
      if (children == null || children.isEmpty) return '';
      return children.map(_extractText).join();
    }
    return '';
  }

  String? _extractLanguage(md.Element element) {
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is! md.Element || child.tag != 'code') continue;
      final className = child.attributes['class'];
      if (className == null || className.isEmpty) continue;
      for (final part in className.split(' ')) {
        if (!part.startsWith('language-')) continue;
        final language = part.substring('language-'.length).trim();
        if (language.isNotEmpty) return language;
      }
    }
    return null;
  }
}
