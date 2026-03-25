package com.stockpulse.radar

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

class MonitorForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        ensureChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val summary = intent?.getStringExtra(summaryArgument()).orEmpty().ifBlank {
            defaultSummary()
        }
        startForeground(notificationId(), buildNotification(this, summary))
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL_ID = "stock_monitor_guard"
        private const val CHANNEL_NAME = "股票异动后台监控"
        private const val NOTIFICATION_ID = 20031

        fun updateSummary(context: Context, summary: String) {
            ensureChannel(context)
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(notificationId(), buildNotification(context, summary.ifBlank { defaultSummary() }))
        }

        private fun buildNotification(context: Context, summary: String): Notification {
            val launchIntent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentMutabilityFlag(),
            )

            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle("股票异动雷达后台监控中")
                .setContentText(summary)
                .setSmallIcon(android.R.drawable.ic_popup_sync)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                return
            }
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) != null) {
                return
            }
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "保持股票监控常驻通知，尽量降低后台被系统回收的概率。"
            }
            manager.createNotificationChannel(channel)
        }

        private fun notificationId(): Int = NOTIFICATION_ID

        private fun pendingIntentMutabilityFlag(): Int {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        }

        private fun defaultSummary(): String = "等待下一次行情刷新。"

        private fun summaryArgument(): String = "summary"
    }
}
