import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/slash_command_utils.dart';

void main() {
  const commands = <AIControlOption>[
    AIControlOption(
      id: 'review',
      label: '/review',
      description: 'Review code changes',
    ),
    AIControlOption(
      id: 'plan',
      label: '/plan',
      description: 'Create implementation plan',
    ),
  ];

  test('extractSlashCommandQuery 仅在输入命令头时返回查询串', () {
    expect(extractSlashCommandQuery('/'), '');
    expect(extractSlashCommandQuery('/rev'), 'rev');
    expect(extractSlashCommandQuery('/review '), isNull);
    expect(extractSlashCommandQuery(' /review'), isNull);
    expect(extractSlashCommandQuery('hello'), isNull);
  });

  test('parseSlashCommandInvocation 只匹配已知命令并提取参数', () {
    final invocation = parseSlashCommandInvocation(
      '/review branch-a',
      commands,
    );

    expect(invocation, isNotNull);
    expect(invocation!.commandName, 'review');
    expect(invocation.arguments, 'branch-a');
    expect(invocation.rawText, '/review branch-a');

    expect(parseSlashCommandInvocation('/unknown task', commands), isNull);
    expect(parseSlashCommandInvocation('/etc/hosts', commands), isNull);
  });

  test('全角 slash 也能触发查询和命令解析', () {
    expect(extractSlashCommandQuery('／'), '');
    expect(extractSlashCommandQuery('／rev'), 'rev');

    final invocation = parseSlashCommandInvocation('／review 分支-a', commands);

    expect(invocation, isNotNull);
    expect(invocation!.commandName, 'review');
    expect(invocation.arguments, '分支-a');
    expect(invocation.rawText, '／review 分支-a');
  });
}
