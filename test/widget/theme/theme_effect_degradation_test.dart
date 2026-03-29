import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/core/theme/app_theme_extension.dart';
import 'package:ssh_ai_terminal/data/models/theme_runtime_options.dart';
import 'package:ssh_ai_terminal/presentation/widgets/sparkline_background.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/aurora_border_glow.dart';

void main() {
  testWidgets('SparklineBackground and Shader disables in Eco mode', (WidgetTester tester) async {
    // 构造测试主题（模拟 Eco 模式下的 ThemeData）
    final mockTheme = ThemeData().copyWith(
      extensions: [
        const AppThemeExtension(
          aiAccentColor: Colors.purple,
          successColor: Colors.green,
          warningColor: Colors.orange,
          errorColor: Colors.red,
          performanceMode: ThemePerformanceMode.eco,
          enableSparkline: false,
          enableAuroraGlow: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: mockTheme,
        home: Scaffold(
          body: Column(
            children: [
              SparklineBackground(
                data: [0.1, 0.2, 0.3],
                color: Colors.blue,
              ),
              AuroraBorderGlow(
                aiState: AIBorderState.running,
                child: const Text('AuroraGlow'),
              ),
            ],
          ),
        ),
      ),
    );

    // Eco 模式下，SparklineBackground 的 body 返回 SizedBox.shrink()
    // 通过判断 CustomPaint 是否存在来验证
    expect(find.byType(CustomPaint), findsNothing);

    // AuroraBorderGlow 没有渲染 shader mask（退化为直接返回 child）
    // 它的内部 ShaderBuilder/CustomPaint 会消失，只有 child(Text) 还在
    final childText = find.text('AuroraGlow');
    expect(childText, findsOneWidget);
    // TODO: A more strict check would mock shaders and test the pipeline, but this verifies the logic block is hit.
  });
}
