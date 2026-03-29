import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';
import 'package:flutter_highlighter/themes/atom-one-light.dart';

/// 魔法代码块渲染引擎
class AIMessageMarkdown extends StatelessWidget {
  const AIMessageMarkdown({
    super.key,
    required this.content,
    this.isError = false,
    this.style,
    this.onRunCode,
  });

  final String content;
  final bool isError;
  final TextStyle? style;
  final void Function(String)? onRunCode; // 核心：一键运行代码回调

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onSurface;
    
    return MarkdownBody(
      data: content,
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
        p: style ?? TextStyle(
          color: textColor,
          fontSize: 15,
          height: 1.6,
        ),
        h1: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
        h2: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
        h3: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
        code: TextStyle(
          fontFamily: 'JetBrainsMono',
          backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
          border: Border(left: BorderSide(color: colorScheme.primary, width: 4)),
        ),
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
