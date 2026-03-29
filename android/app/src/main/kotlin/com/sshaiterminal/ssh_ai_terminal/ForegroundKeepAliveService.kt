package com.sshaiterminal.ssh_ai_terminal

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ForegroundKeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_START_OR_UPDATE, null -> {
                val title = intent?.getStringExtra(EXTRA_TITLE)
                    ?: "ForgeTerm AI 正在后台保持连接"
                val text = intent?.getStringExtra(EXTRA_TEXT)
                    ?: "正在保持 SSH 会话"
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(title = title, text = text),
                )
                return START_STICKY
            }

            else -> {
                return START_NOT_STICKY
            }
        }
    }

    private fun buildNotification(title: String, text: String): Notification {
        val launchIntent =
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "SSH 后台连接",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "保持 SSH 会话、隧道和自动重连在后台继续运行"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val ACTION_START_OR_UPDATE =
            "com.sshaiterminal.ssh_ai_terminal.action.START_OR_UPDATE_FOREGROUND"
        private const val ACTION_STOP =
            "com.sshaiterminal.ssh_ai_terminal.action.STOP_FOREGROUND"
        private const val EXTRA_TITLE = "extra_title"
        private const val EXTRA_TEXT = "extra_text"
        private const val NOTIFICATION_CHANNEL_ID = "ssh_keep_alive"
        private const val NOTIFICATION_ID = 1001

        fun startIntent(context: Context, title: String, text: String): Intent {
            return Intent(context, ForegroundKeepAliveService::class.java).apply {
                action = ACTION_START_OR_UPDATE
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
            }
        }

        fun stopIntent(context: Context): Intent {
            return Intent(context, ForegroundKeepAliveService::class.java).apply {
                action = ACTION_STOP
            }
        }
    }
}
