import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';

const _asciiSlash = '/';
const _fullWidthSlash = '／';

class AISlashCommandInvocation {
  const AISlashCommandInvocation({
    required this.commandName,
    required this.arguments,
    required this.rawText,
  });

  final String commandName;
  final String arguments;
  final String rawText;
}

String normalizeLeadingSlashCharacter(String text) {
  if (text.startsWith(_fullWidthSlash)) {
    return '$_asciiSlash${text.substring(1)}';
  }
  return text;
}

bool hasSlashCommandPrefix(String text) {
  final trimmedLeft = text.trimLeft();
  return normalizeLeadingSlashCharacter(trimmedLeft).startsWith(_asciiSlash);
}

String? extractSlashCommandQuery(String text) {
  final normalized = normalizeLeadingSlashCharacter(text);
  final match = RegExp(r'^/(\S*)$').firstMatch(normalized);
  if (match == null) {
    return null;
  }
  return match.group(1) ?? '';
}

List<AIControlOption> filterSlashCommands(
  List<AIControlOption> commands,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return List<AIControlOption>.of(commands);
  }

  return commands
      .where((command) {
        final id = command.id.toLowerCase();
        final label = command.label.toLowerCase();
        final description = command.description?.toLowerCase() ?? '';
        return id.contains(normalized) ||
            label.contains(normalized) ||
            description.contains(normalized);
      })
      .toList(growable: false);
}

AISlashCommandInvocation? parseSlashCommandInvocation(
  String text,
  List<AIControlOption> commands,
) {
  final trimmed = text.trim();
  final normalized = normalizeLeadingSlashCharacter(trimmed);
  if (!normalized.startsWith(_asciiSlash)) {
    return null;
  }

  final match = RegExp(r'^/(\S+)(?:\s+(.*))?$').firstMatch(normalized);
  if (match == null) {
    return null;
  }

  final commandName = match.group(1)?.trim();
  if (commandName == null || commandName.isEmpty) {
    return null;
  }

  final exists = commands.any((command) => command.id == commandName);
  if (!exists) {
    return null;
  }

  return AISlashCommandInvocation(
    commandName: commandName,
    arguments: match.group(2)?.trim() ?? '',
    rawText: trimmed,
  );
}
