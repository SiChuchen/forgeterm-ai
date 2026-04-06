const String kAiThinkingStartMarker = '[[FORGETERM_THINKING]]';
const String kAiThinkingEndMarker = '[[/FORGETERM_THINKING]]';

enum AIMessageSegmentType {
  markdown,
  thinking,
}

class AIMessageSegment {
  const AIMessageSegment({required this.type, required this.content});

  const AIMessageSegment.markdown(this.content)
      : type = AIMessageSegmentType.markdown,
        assert(content != '');

  const AIMessageSegment.thinking(this.content)
      : type = AIMessageSegmentType.thinking,
        assert(content != '');

  final AIMessageSegmentType type;
  final String content;
}

String buildAiThinkingBlock(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return '$kAiThinkingStartMarker\n$trimmed\n$kAiThinkingEndMarker';
}

List<AIMessageSegment> parseAiMessageSegments(String content) {
  final segments = <AIMessageSegment>[];
  var cursor = 0;

  void pushMarkdown(String value) {
    if (value.isEmpty) {
      return;
    }
    segments.add(AIMessageSegment.markdown(value));
  }

  while (cursor < content.length) {
    final start = content.indexOf(kAiThinkingStartMarker, cursor);
    if (start < 0) {
      pushMarkdown(content.substring(cursor));
      break;
    }

    if (start > cursor) {
      pushMarkdown(content.substring(cursor, start));
    }

    final thinkingStart = start + kAiThinkingStartMarker.length;
    final end = content.indexOf(kAiThinkingEndMarker, thinkingStart);
    if (end < 0) {
      pushMarkdown(content.substring(start));
      break;
    }

    final thinkingContent = content.substring(thinkingStart, end).trim();
    if (thinkingContent.isNotEmpty) {
      segments.add(AIMessageSegment.thinking(thinkingContent));
    }
    cursor = end + kAiThinkingEndMarker.length;
  }

  return _mergeAiMessageSegments(segments);
}

String stripAiMessageMarkup(String content) {
  final segments = parseAiMessageSegments(content);
  if (segments.isEmpty) {
    return content
        .replaceAll(kAiThinkingStartMarker, '')
        .replaceAll(kAiThinkingEndMarker, '')
        .trim();
  }

  return segments
      .map((segment) => segment.content.trim())
      .where((segment) => segment.isNotEmpty)
      .join('\n\n')
      .trim();
}

String extractAiAnswerText(String content) {
  final segments = parseAiMessageSegments(content);
  final markdownOnly = segments.isEmpty
      ? content
          .replaceAll(kAiThinkingStartMarker, '')
          .replaceAll(kAiThinkingEndMarker, '')
      : segments
          .where((segment) => segment.type == AIMessageSegmentType.markdown)
          .map((segment) => segment.content)
          .join();

  return _stripCopyExcludedSections(markdownOnly);
}

List<AIMessageSegment> _mergeAiMessageSegments(List<AIMessageSegment> segments) {
  if (segments.length < 2) {
    return segments;
  }

  final merged = <AIMessageSegment>[];
  int? thinkingIndex;

  for (final segment in segments) {
    switch (segment.type) {
      case AIMessageSegmentType.thinking:
        final trimmed = segment.content.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        if (thinkingIndex == null) {
          merged.add(AIMessageSegment.thinking(trimmed));
          thinkingIndex = merged.length - 1;
          continue;
        }

        final existing = merged[thinkingIndex].content.trimRight();
        merged[thinkingIndex] = AIMessageSegment.thinking(
          '$existing\n\n$trimmed',
        );
        break;
      case AIMessageSegmentType.markdown:
        if (segment.content.isEmpty) {
          continue;
        }
        final whitespaceOnly = segment.content.trim().isEmpty;
        if (whitespaceOnly && thinkingIndex != null) {
          continue;
        }

        if (merged.isNotEmpty &&
            merged.last.type == AIMessageSegmentType.markdown) {
          final previous = merged.removeLast();
          merged.add(
            AIMessageSegment.markdown(previous.content + segment.content),
          );
          continue;
        }

        merged.add(segment);
        break;
    }
  }

  return merged;
}

String _stripCopyExcludedSections(String content) {
  final sections = content
      .replaceAll(kAiThinkingStartMarker, '')
      .replaceAll(kAiThinkingEndMarker, '')
      .split(RegExp(r'\n{2,}'))
      .map((section) => section.trim())
      .where((section) => section.isNotEmpty)
      .where((section) => !_isCopyExcludedSection(section))
      .toList(growable: false);

  return sections.join('\n\n').trim();
}

bool _isCopyExcludedSection(String section) {
  final firstLine = section
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');

  return firstLine == '**使用统计**' || firstLine.startsWith('**工具调用');
}
