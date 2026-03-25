package com.stockpulse.radar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MonitorForegroundService : Service(), TextToSpeech.OnInitListener {
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val engine = NativeMonitorEngine()
    private val runningRefresh = AtomicBoolean(false)
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false
    private var lastSummary: String = defaultSummary()

    private val pollRunnable = object : Runnable {
        override fun run() {
            triggerRefresh(reschedule = true)
        }
    }

    override fun onCreate() {
        super.onCreate()
        ensureChannel(this)
        ensureTts()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START_MONITOR
        when (action) {
            ACTION_START_MONITOR -> {
                val summary = intent?.getStringExtra(summaryArgument()).orEmpty().ifBlank {
                    loadBootSummary()
                }
                startAsForeground(summary)
                ensureMonitoringActive(triggerImmediateRefresh = true)
            }

            ACTION_REFRESH_NOW -> {
                startAsForeground(lastSummary)
                ensureMonitoringActive(triggerImmediateRefresh = true)
            }

            ACTION_RELOAD_MONITOR -> {
                startAsForeground(loadBootSummary())
                ensureMonitoringActive(triggerImmediateRefresh = false)
            }

            ACTION_STOP_MONITOR -> {
                stopMonitoring()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }

            else -> {
                startAsForeground(loadBootSummary())
                ensureMonitoringActive(triggerImmediateRefresh = true)
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        executor.shutdownNow()
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val restartIntent = Intent(applicationContext, MonitorForegroundService::class.java).apply {
            action = ACTION_RELOAD_MONITOR
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            applicationContext.startForegroundService(restartIntent)
        } else {
            applicationContext.startService(restartIntent)
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onInit(status: Int) {
        ttsReady = status == TextToSpeech.SUCCESS
        if (ttsReady) {
            val locale = Locale.SIMPLIFIED_CHINESE
            val availability = textToSpeech?.isLanguageAvailable(locale) ?: TextToSpeech.LANG_NOT_SUPPORTED
            if (availability >= TextToSpeech.LANG_AVAILABLE) {
                textToSpeech?.language = locale
            }
            textToSpeech?.setSpeechRate(1.0f)
            textToSpeech?.setPitch(1.0f)
        }
    }

    private fun ensureMonitoringActive(triggerImmediateRefresh: Boolean) {
        handler.removeCallbacks(pollRunnable)
        if (!MonitorStorage.isServiceEnabled(this)) {
            stopMonitoring()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        if (triggerImmediateRefresh) {
            triggerRefresh(reschedule = true)
        } else {
            scheduleNextPoll(loadSettings().pollIntervalSeconds)
        }
    }

    private fun stopMonitoring() {
        handler.removeCallbacks(pollRunnable)
        MonitorStorage.updateStatus(
            context = this,
            checkedAtMillis = System.currentTimeMillis(),
            message = "后台监控守护已关闭。",
        )
        updateSummary(this, "后台监控守护已关闭。")
    }

    private fun triggerRefresh(reschedule: Boolean) {
        if (!runningRefresh.compareAndSet(false, true)) {
            if (reschedule) {
                scheduleNextPoll(loadSettings().pollIntervalSeconds)
            }
            return
        }

        executor.execute {
            try {
                val settings = loadSettings()
                val watchlist = MonitorStorage.loadWatchlist(this)
                val rules = MonitorStorage.loadRules(this)
                val runtimeState = MonitorStorage.loadRuntimeState(this)
                val result = engine.refresh(
                    watchlist = watchlist,
                    rules = rules,
                    runtimeState = runtimeState,
                )
                MonitorStorage.saveRuntimeState(this, runtimeState)
                val historyEntries = mutableListOf<NativeAlertHistoryEntry>()
                val soundEnabled = settings.soundEnabled
                result.triggers.forEach { trigger ->
                    val playedSound = if (soundEnabled) speak(trigger.spokenText) else false
                    historyEntries += NativeAlertHistoryEntry(
                        id = "${trigger.rule.id}-${trigger.triggeredAtMillis}",
                        ruleId = trigger.rule.id,
                        ruleType = trigger.rule.type,
                        stockCode = trigger.quote.code,
                        stockName = trigger.quote.name,
                        market = trigger.quote.market,
                        triggeredAtIso = MonitorStorage.formatIso8601(trigger.triggeredAtMillis),
                        currentPrice = trigger.quote.lastPrice,
                        referencePrice = trigger.referencePrice,
                        changeAmount = trigger.changeAmount,
                        changePercent = trigger.changePercent,
                        message = trigger.message,
                        spokenText = trigger.spokenText,
                        playedSound = playedSound,
                    )
                }
                MonitorStorage.appendHistoryEntries(this, historyEntries)
                val summary = if (historyEntries.isNotEmpty()) {
                    "${result.summary} 最新：${historyEntries.first().message}"
                } else {
                    result.summary
                }
                MonitorStorage.updateStatus(this, result.checkedAtMillis, summary)
                handler.post {
                    updateSummary(this, summary)
                    if (reschedule) {
                        scheduleNextPoll(settings.pollIntervalSeconds)
                    }
                }
            } finally {
                runningRefresh.set(false)
            }
        }
    }

    private fun scheduleNextPoll(intervalSeconds: Int) {
        handler.removeCallbacks(pollRunnable)
        handler.postDelayed(pollRunnable, intervalSeconds.coerceIn(15, 300) * 1000L)
    }

    private fun ensureTts() {
        if (textToSpeech == null) {
            textToSpeech = TextToSpeech(applicationContext, this)
        }
    }

    private fun speak(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) {
            return false
        }
        ensureTts()
        if (!ttsReady) {
            return false
        }
        return textToSpeech?.speak(
            trimmed,
            TextToSpeech.QUEUE_ADD,
            null,
            "stock-pulse-service-${System.currentTimeMillis()}",
        ) == TextToSpeech.SUCCESS
    }

    private fun startAsForeground(summary: String) {
        lastSummary = summary.ifBlank { defaultSummary() }
        startForeground(notificationId(), buildNotification(this, lastSummary))
    }

    private fun loadBootSummary(): String {
        return loadSettings().lastMessage.ifBlank { defaultSummary() }
    }

    private fun loadSettings(): NativeMonitorSettings = MonitorStorage.loadSettings(this)

    companion object {
        private const val CHANNEL_ID = "stock_monitor_guard"
        private const val CHANNEL_NAME = "股票异动后台监控"
        private const val NOTIFICATION_ID = 20031
        const val ACTION_START_MONITOR = "com.stockpulse.radar.action.START_MONITOR"
        const val ACTION_REFRESH_NOW = "com.stockpulse.radar.action.REFRESH_NOW"
        const val ACTION_RELOAD_MONITOR = "com.stockpulse.radar.action.RELOAD_MONITOR"
        const val ACTION_STOP_MONITOR = "com.stockpulse.radar.action.STOP_MONITOR"

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
                .setStyle(NotificationCompat.BigTextStyle().bigText(summary))
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
