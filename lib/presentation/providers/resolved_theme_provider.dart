import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/data/models/theme_profile.dart';
import 'package:ssh_ai_terminal/data/models/theme_runtime_options.dart';
import 'package:ssh_ai_terminal/presentation/providers/theme_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/theme_runtime_provider.dart';

class ResolvedTheme {
  final ThemeProfile profile;
  final ThemeRuntimeOptions options;

  const ResolvedTheme({
    required this.profile,
    required this.options,
  });
}

final resolvedThemeProvider = Provider<ResolvedTheme>((ref) {
  final profile = ref.watch(themeStateProvider);
  final options = ref.watch(themeRuntimeStateProvider);
  
  return ResolvedTheme(
    profile: profile,
    options: options,
  );
});
