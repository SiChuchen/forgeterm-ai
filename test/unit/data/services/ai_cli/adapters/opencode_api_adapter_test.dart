import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/adapters/opencode_api_adapter.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/ai_message_markup.dart';

void main() {
  group('OpenCodeApiAdapter.extractDisplayContentForTest', () {
    test('保留 reasoning 块并转换为可折叠思考标记', () {
      final content = OpenCodeApiAdapter.extractDisplayContentForTest({
        'parts': [
          {
            'type': 'reasoning',
            'text': '先检查输入和上下文，再生成答案。',
          },
          {
            'type': 'text',
            'text': '这是最终回复。',
          },
        ],
      });

      final segments = parseAiMessageSegments(content);
      expect(segments, hasLength(2));
      expect(segments.first.type, AIMessageSegmentType.thinking);
      expect(segments.first.content, '先检查输入和上下文，再生成答案。');
      expect(segments.last.type, AIMessageSegmentType.markdown);
      expect(segments.last.content, '这是最终回复。');
    });

    test('工具调用块会归并到思考标记内', () {
      final content = OpenCodeApiAdapter.extractDisplayContentForTest({
        'parts': [
          {
            'type': 'tool',
            'tool': 'read_file',
            'state': {
              'status': 'completed',
              'input': {
                'path': '/tmp/demo.txt',
              },
              'output': 'ok',
            },
          },
          {
            'type': 'text',
            'text': '这是最终回复。',
          },
        ],
      });

      final segments = parseAiMessageSegments(content);
      expect(segments, hasLength(2));
      expect(segments.first.type, AIMessageSegmentType.thinking);
      expect(segments.first.content, contains('工具调用'));
      expect(segments.first.content, contains('read_file'));
      expect(segments.last.type, AIMessageSegmentType.markdown);
      expect(segments.last.content, '这是最终回复。');
    });
  });

  group('OpenCodeApiAdapter.extractConfiguredProviderCatalogForTest', () {
    test('只返回已配置 provider 下的模型列表', () {
      final catalog = OpenCodeApiAdapter.extractConfiguredProviderCatalogForTest(
        {
          'providers': [
            {
              'id': 'openai',
              'name': 'OpenAI',
              'source': 'env',
              'models': {
                'gpt-4o': {
                  'id': 'gpt-4o',
                  'name': 'GPT-4o',
                },
                'gpt-4.1': {
                  'id': 'gpt-4.1',
                  'name': 'GPT-4.1',
                  'variants': {
                    'high': {},
                  },
                },
              },
            },
            {
              'id': 'anthropic',
              'name': 'Anthropic',
              'source': 'config',
              'models': {
                'claude-sonnet-4': {
                  'id': 'claude-sonnet-4',
                  'name': 'Claude Sonnet 4',
                },
              },
            },
          ],
          'default': {
            'openai': 'gpt-4o',
            'anthropic': 'claude-sonnet-4',
          },
        },
        providerId: 'openai',
        modelId: 'gpt-4.1',
      );

      expect(catalog.providerOptions, hasLength(2));
      expect(
        catalog.providerOptions.firstWhere((item) => item.id == 'openai').description,
        '已添加 · 环境变量',
      );
      expect(
        catalog.modelOptions.map((item) => item.id),
        [
          'anthropic/claude-sonnet-4',
          'openai/gpt-4o',
          'openai/gpt-4.1',
        ],
      );
      expect(
        catalog.modelOptions.firstWhere((item) => item.id == 'openai/gpt-4o').description,
        'OpenAI',
      );
      expect(catalog.variantOptions.map((item) => item.id), ['high']);
    });

    test('保留服务器当前模型并据此推导 variant', () {
      final catalog = OpenCodeApiAdapter.extractConfiguredProviderCatalogForTest(
        {
          'providers': [
            {
              'id': 'openai',
              'name': 'OpenAI',
              'source': 'env',
              'models': {
                'gpt-4o': {
                  'id': 'gpt-4o',
                  'name': 'GPT-4o',
                },
                'gpt-4.1': {
                  'id': 'gpt-4.1',
                  'name': 'GPT-4.1',
                  'variants': {
                    'high': {},
                  },
                },
              },
            },
          ],
          'default': {
            'openai': 'gpt-4o',
          },
        },
        serverCurrentModelRef: 'openai/gpt-4.1',
      );

      expect(catalog.serverCurrentModelRef, 'openai/gpt-4.1');
      expect(catalog.variantOptions.map((item) => item.id), ['high']);
    });
  });

  group('OpenCodeApiAdapter.extractRenderableChunksFromUpdatedPartForTest', () {
    test('完整 reasoning part 会转换成 thinking chunk', () {
      final chunks =
          OpenCodeApiAdapter.extractRenderableChunksFromUpdatedPartForTest(
        {
          'id': 'part-reasoning-1',
          'type': 'reasoning',
          'text': '先分析需求，再生成答案。',
          'time': {
            'start': 1,
            'end': 2,
          },
        },
        emittedPartIds: <String>{},
      );

      expect(chunks, hasLength(1));
      expect(chunks.single.type, AIChunkType.thinking);
      expect(chunks.single.content, '先分析需求，再生成答案。');
    });

    test('已通过 delta 流出的 text part 不会在 completed update 时重复追加', () {
      final emittedPartIds = <String>{};
      final streamedTextPartIds = <String>{'part-text-1'};
      final chunks =
          OpenCodeApiAdapter.extractRenderableChunksFromUpdatedPartForTest(
        {
          'id': 'part-text-1',
          'type': 'text',
          'text': '最终答案',
          'time': {
            'start': 1,
            'end': 2,
          },
        },
        emittedPartIds: emittedPartIds,
        streamedTextPartIds: streamedTextPartIds,
      );

      expect(chunks, isEmpty);
      expect(emittedPartIds, contains('part-text-1'));
    });

    test('已通过 delta 流出的 reasoning part 不会在 completed update 时重复追加', () {
      final emittedPartIds = <String>{};
      final streamedThinkingPartIds = <String>{'part-thinking-1'};
      final chunks =
          OpenCodeApiAdapter.extractRenderableChunksFromUpdatedPartForTest(
        {
          'id': 'part-thinking-1',
          'type': 'reasoning',
          'text': '先推理，再回答。',
          'time': {
            'start': 1,
            'end': 2,
          },
        },
        emittedPartIds: emittedPartIds,
        streamedThinkingPartIds: streamedThinkingPartIds,
      );

      expect(chunks, isEmpty);
      expect(emittedPartIds, contains('part-thinking-1'));
    });

    test('完整 tool part 会转换成 toolUse chunk', () {
      final chunks =
          OpenCodeApiAdapter.extractRenderableChunksFromUpdatedPartForTest(
        {
          'id': 'part-tool-1',
          'type': 'tool',
          'tool': 'read_file',
          'state': {
            'status': 'completed',
            'input': {
              'path': '/tmp/demo.txt',
            },
            'output': 'ok',
          },
        },
        emittedPartIds: <String>{},
      );

      expect(chunks, hasLength(1));
      expect(chunks.single.type, AIChunkType.toolUse);
      expect(chunks.single.content, contains('工具调用'));
      expect(chunks.single.content, contains('read_file'));
    });
  });
}
