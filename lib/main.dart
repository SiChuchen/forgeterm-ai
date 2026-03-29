import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/data/services/hive_init_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveInitService.init();
  runApp(const ProviderScope(child: SSHAITerminalApp()));
}
