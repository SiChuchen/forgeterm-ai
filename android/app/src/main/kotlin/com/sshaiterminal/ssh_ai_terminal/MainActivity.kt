package com.sshaiterminal.ssh_ai_terminal

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ssh_ai_terminal/foreground_service",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startOrUpdate" -> {
                    try {
                        val title = call.argument<String>("title")
                            ?: "ForgeTerm AI 正在后台保持连接"
                        val text = call.argument<String>("text")
                            ?: "正在保持 SSH 会话"
                        ContextCompat.startForegroundService(
                            this,
                            ForegroundKeepAliveService.startIntent(this, title, text),
                        )
                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "foreground_start_failed",
                            error.message,
                            null,
                        )
                    }
                }

                "stop" -> {
                    try {
                        val intent: Intent = ForegroundKeepAliveService.stopIntent(this)
                        stopService(intent)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "foreground_stop_failed",
                            error.message,
                            null,
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
