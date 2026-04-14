package com.stockpulse.radar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MonitorForegroundService : Service(), TextToSpeech.OnInitListener {
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val engine = NativeMonitorEngine()
    private val runningRefresh = AtomicBoolean(false)
    private val ttsLock = Object()
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false
    private var ttsInitCompleted = false
    private var lastSummary: String = defaultSummary()

    private val pollRunnable = object : Runnable {
        override fun run() {
            triggerRefresh(reschedule = true)
        }
    }

    override fun onCreate() {
        super.onCreate()
        ensureChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START_MONITOR
        return try {
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
            START_STICKY
        } catch (error: Exception) {
            Log.e(TAG, "Failed to start monitor foreground service", error)
            MonitorStorage.disableService(
                context = this,
                message = "后台监控启动失败：${error.message ?: error.javaClass.simpleName}；已自动关闭后台监控。",
            )
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            START_NOT_STICKY
        }
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
        if (MonitorStorage.isServiceEnabled(this)) {
            MonitorStorage.disableService(
                context = this,
                message = "后台监控在应用任务被移除后已暂停。为避免系统限制导致异常，请重新打开应用后手动开启。",
            )
            handler.removeCallbacks(pollRunnable)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onInit(status: Int) {
        synchronized(ttsLock) {
            ttsInitCompleted = true
            val initialized = status == TextToSpeech.SUCCESS
            val configuredPreferredVoice = if (initialized) configureTtsVoice() else false
            ttsReady = initialized
            if (ttsReady) {
                configureTtsAudio()
                textToSpeech?.setSpeechRate(1.0f)
                textToSpeech?.setPitch(1.0f)
            }
            Log.i(
                TAG,
                "Foreground service TTS init status=$status ready=$ttsReady preferredVoice=$configuredPreferredVoice",
            )
            ttsLock.notifyAll()
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
            scheduleNextPoll(loadSettings().pollIntervalSeconds, updateClosedSummary = true)
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
        val checkedAtMillis = System.currentTimeMillis()
        val marketSession = AshareMarketSchedule.currentSession(checkedAtMillis)
        if (!marketSession.isTradingOpen) {
            val summary = AshareMarketSchedule.buildClosedSummary(marketSession)
            MonitorStorage.updateStatus(
                context = this,
                checkedAtMillis = checkedAtMillis,
                message = summary,
            )
            updateSummary(this, summary)
            scheduleNextPoll(loadSettings().pollIntervalSeconds)
            return
        }

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
                    settings = settings,
                )
                MonitorStorage.saveRuntimeState(this, runtimeState)
                val historyEntries = mutableListOf<NativeAlertHistoryEntry>()
                val soundEnabled = settings.soundEnabled
                result.triggers.forEach { trigger ->
                    val playedSound = if (soundEnabled) speak(trigger.spokenText) else false
                    historyEntries += NativeAlertHistoryEntry(
                        id = "${trigger.rule.id}-${trigger.quote.code}-${trigger.triggeredAtMillis}",
                        ruleId = trigger.rule.id,
                        ruleType = trigger.rule.type,
                        stockCode = trigger.quote.code,
                        stockName = trigger.quote.name,
                        market = trigger.quote.market,
                        securityTypeName = trigger.quote.securityTypeName,
                        priceDecimalDigits = trigger.quote.priceDecimalDigits,
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
            } catch (error: Exception) {
                Log.e(TAG, "Monitor refresh failed unexpectedly", error)
                val settings = loadSettings()
                val summary =
                    "后台监控刷新失败：${error.message ?: error.javaClass.simpleName}"
                MonitorStorage.updateStatus(this, checkedAtMillis, summary)
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

    private fun scheduleNextPoll(intervalSeconds: Int, updateClosedSummary: Boolean = false) {
        handler.removeCallbacks(pollRunnable)
        val nowMillis = System.currentTimeMillis()
        val marketSession = AshareMarketSchedule.currentSession(nowMillis)
        if (!marketSession.isTradingOpen) {
            if (updateClosedSummary) {
                val summary = AshareMarketSchedule.buildClosedSummary(marketSession)
                MonitorStorage.updateStatus(
                    context = this,
                    checkedAtMillis = nowMillis,
                    message = summary,
                )
                updateSummary(this, summary)
            }
            handler.postDelayed(pollRunnable, marketSession.delayUntilNextOpenMillis(nowMillis))
            return
        }

        handler.postDelayed(
            pollRunnable,
            AshareMarketSchedule.normalizePollIntervalSeconds(intervalSeconds) * 1000L,
        )
    }

    private fun ensureTts(): Boolean {
        if (textToSpeech != null) {
            return true
        }
        return runCatching {
            synchronized(ttsLock) {
                ttsReady = false
                ttsInitCompleted = false
            }
            textToSpeech = TextToSpeech(applicationContext, this)
            true
        }.getOrElse { error ->
            Log.w(TAG, "Unable to initialize TTS in foreground service", error)
            false
        }
    }

    private fun speak(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) {
            return false
        }
        if (!awaitTtsReady()) {
            Log.w(TAG, "Foreground service TTS not ready; skipping speech")
            return false
        }
        val utteranceId = "stock-pulse-service-${System.currentTimeMillis()}"
        val queued = textToSpeech?.speak(
            trimmed,
            TextToSpeech.QUEUE_ADD,
            null,
            utteranceId,
        ) == TextToSpeech.SUCCESS
        if (!queued) {
            Log.w(TAG, "Foreground service TTS speak returned non-success for $utteranceId")
        }
        return queued
    }

    private fun awaitTtsReady(timeoutMillis: Long = 2500L): Boolean {
        if (!ensureTts()) {
            return false
        }
        val deadline = System.currentTimeMillis() + timeoutMillis
        synchronized(ttsLock) {
            while (!ttsInitCompleted && System.currentTimeMillis() < deadline) {
                val remaining = deadline - System.currentTimeMillis()
                if (remaining <= 0) {
                    break
                }
                runCatching {
                    ttsLock.wait(remaining)
                }.onFailure {
                    Thread.currentThread().interrupt()
                    return false
                }
            }
            return ttsReady
        }
    }

    private fun configureTtsVoice(): Boolean {
        val tts = textToSpeech ?: return false
        val candidateLocales = linkedSetOf(
            Locale.SIMPLIFIED_CHINESE,
            Locale.CHINESE,
            Locale.getDefault(),
        )
        for (locale in candidateLocales) {
            val availability = tts.isLanguageAvailable(locale)
            if (availability >= TextToSpeech.LANG_AVAILABLE) {
                val result = tts.setLanguage(locale)
                if (result >= TextToSpeech.LANG_AVAILABLE) {
                    Log.i(TAG, "Foreground service selected TTS locale: $locale")
                    return true
                }
            }
        }
        Log.w(TAG, "Foreground service preferred Chinese TTS locale unavailable; falling back to engine default voice")
        return false
    }

    private fun configureTtsAudio() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return
        }
        runCatching {
            textToSpeech?.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
        }.onFailure { error ->
            Log.w(TAG, "Unable to apply foreground service TTS audio attributes", error)
        }
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
        private const val TAG = "MonitorForegroundSvc"
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
