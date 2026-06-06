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
import android.speech.tts.Voice
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
    private var ttsInitializationStarted = false
    private var lastSummary: String = defaultSummary()

    private val pollRunnable = object : Runnable {
        override fun run() {
            triggerRefresh(reschedule = true)
        }
    }

    override fun onCreate() {
        super.onCreate()
        ensureChannel(this)
        logDiagnostic("info", "service", "前台监控服务已创建。")
        prewarmTtsIfEnabled()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START_MONITOR
        return try {
            when (action) {
                ACTION_START_MONITOR -> {
                    logDiagnostic("info", "service", "收到后台监控启动请求。")
                    val summary = intent?.getStringExtra(summaryArgument()).orEmpty().ifBlank {
                        loadBootSummary()
                    }
                    startAsForeground(summary)
                    ensureMonitoringActive(triggerImmediateRefresh = true)
                }

                ACTION_REFRESH_NOW -> {
                    logDiagnostic("info", "service", "收到后台即时刷新请求。")
                    startAsForeground(lastSummary)
                    ensureMonitoringActive(triggerImmediateRefresh = true)
                }

                ACTION_RELOAD_MONITOR -> {
                    logDiagnostic("info", "service", "收到后台监控恢复请求。")
                    startAsForeground(loadBootSummary())
                    ensureMonitoringActive(triggerImmediateRefresh = false)
                }

                ACTION_STOP_MONITOR -> {
                    logDiagnostic("info", "service", "收到后台监控停止请求。")
                    stopMonitoring()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }

                ACTION_TEST_ALERT -> {
                    logDiagnostic("info", "service", "收到后台提醒链路测试请求。")
                    startAsForeground(testAlertSummary())
                    triggerBackgroundAlertTest()
                }

                else -> {
                    logDiagnostic("warning", "service", "收到未知后台监控请求：$action")
                    startAsForeground(loadBootSummary())
                    ensureMonitoringActive(triggerImmediateRefresh = true)
                }
            }
            START_STICKY
        } catch (error: Exception) {
            Log.e(TAG, "Failed to start monitor foreground service", error)
            if (action == ACTION_TEST_ALERT) {
                val message = "后台提醒测试启动失败：${error.message ?: error.javaClass.simpleName}"
                MonitorStorage.updateStatus(
                    context = this,
                    checkedAtMillis = System.currentTimeMillis(),
                    message = message,
                )
                logDiagnostic("error", "service", message)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            val message =
                "后台监控启动失败：${error.message ?: error.javaClass.simpleName}；已自动关闭后台监控。"
            logDiagnostic("error", "service", message)
            MonitorStorage.disableService(
                context = this,
                message = message,
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
        logDiagnostic("info", "service", "前台监控服务已销毁。")
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (MonitorStorage.isServiceEnabled(this)) {
            val message = "后台监控在应用任务被移除后已暂停。为避免系统限制导致异常，请重新打开应用后手动开启。"
            logDiagnostic("warning", "service", message)
            MonitorStorage.disableService(
                context = this,
                message = message,
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
            ttsInitializationStarted = false
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
        logDiagnostic(
            if (ttsReady) "info" else "warning",
            "speech",
            if (ttsReady) {
                "前台服务语音初始化完成。"
            } else {
                "前台服务语音初始化失败，状态码：$status。"
            },
        )
    }

    private fun ensureMonitoringActive(triggerImmediateRefresh: Boolean) {
        handler.removeCallbacks(pollRunnable)
        if (!MonitorStorage.isServiceEnabled(this)) {
            logDiagnostic("info", "service", "后台监控未开启，前台服务将停止。")
            stopMonitoring()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        prewarmTtsIfEnabled()
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
            logDiagnostic("info", "refresh", summary, checkedAtMillis)
            scheduleNextPoll(loadSettings().pollIntervalSeconds)
            return
        }

        if (!runningRefresh.compareAndSet(false, true)) {
            logDiagnostic("warning", "refresh", "上一轮后台刷新仍在执行，已跳过本次请求。", checkedAtMillis)
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
                    if (!soundEnabled) {
                        logDiagnostic(
                            "info",
                            "speech",
                            "语音播报已关闭，未播报：${trigger.message}",
                            trigger.triggeredAtMillis,
                        )
                    } else if (!playedSound) {
                        logDiagnostic(
                            "warning",
                            "speech",
                            "前台服务语音播报未成功：${trigger.message}",
                            trigger.triggeredAtMillis,
                        )
                    }
                    val notificationId = (trigger.rule.id + ":" + trigger.quote.code + ":" + trigger.triggeredAtMillis)
                        .hashCode() and Int.MAX_VALUE
                    val notificationPublished = AlertNotificationPublisher.publish(
                        context = this,
                        title = buildAlertNotificationTitle(trigger.quote),
                        message = trigger.message,
                        notificationId = notificationId,
                    )
                    if (!notificationPublished) {
                        logDiagnostic(
                            "warning",
                            "notification",
                            "提醒通知发布失败：${trigger.message}",
                            trigger.triggeredAtMillis,
                        )
                    }
                    logDiagnostic("info", "alert", "触发提醒：${trigger.message}", trigger.triggeredAtMillis)
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
                logDiagnostic(
                    if (result.hasError) "error" else "info",
                    "refresh",
                    summary,
                    result.checkedAtMillis,
                )
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
                logDiagnostic("error", "refresh", summary, checkedAtMillis)
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

    private fun triggerBackgroundAlertTest() {
        executor.execute {
            val timestampMillis = System.currentTimeMillis()
            val message = "股票异动雷达后台提醒测试：通知和语音链路已触发。"
            try {
                val notificationPublished = AlertNotificationPublisher.publish(
                    context = this,
                    title = "后台提醒测试",
                    message = message,
                    notificationId = testAlertNotificationId(timestampMillis),
                )
                if (!notificationPublished) {
                    logDiagnostic("warning", "notification", "后台提醒测试通知发布失败。", timestampMillis)
                }

                val settings = loadSettings()
                val playedSound = if (settings.soundEnabled) {
                    speak(message)
                } else {
                    logDiagnostic("info", "speech", "语音播报已关闭，后台提醒测试未执行语音。", timestampMillis)
                    false
                }
                if (settings.soundEnabled && !playedSound) {
                    logDiagnostic("warning", "speech", "后台提醒测试语音播报未成功。", timestampMillis)
                }

                val summary = when {
                    notificationPublished && playedSound -> "后台提醒测试完成：通知和语音均已请求。"
                    notificationPublished && !settings.soundEnabled -> "后台提醒测试完成：通知已请求，语音播报当前关闭。"
                    notificationPublished -> "后台提醒测试完成：通知已请求，语音未成功。"
                    playedSound -> "后台提醒测试完成：语音已请求，通知未成功。"
                    else -> "后台提醒测试完成：通知和语音均未成功。"
                }
                MonitorStorage.updateStatus(this, timestampMillis, summary)
                logDiagnostic(
                    if (notificationPublished || playedSound || !settings.soundEnabled) "info" else "warning",
                    "service",
                    summary,
                    timestampMillis,
                )
                handler.post {
                    updateSummary(this, summary)
                    restoreOrStopAfterBackgroundAlertTest()
                }
            } catch (error: Exception) {
                val summary = "后台提醒测试失败：${error.message ?: error.javaClass.simpleName}"
                MonitorStorage.updateStatus(this, timestampMillis, summary)
                logDiagnostic("error", "service", summary, timestampMillis)
                handler.post {
                    updateSummary(this, summary)
                    restoreOrStopAfterBackgroundAlertTest()
                }
            }
        }
    }

    private fun restoreOrStopAfterBackgroundAlertTest() {
        if (MonitorStorage.isServiceEnabled(this)) {
            handler.postDelayed(
                {
                    startAsForeground(loadBootSummary())
                    ensureMonitoringActive(triggerImmediateRefresh = false)
                },
                2500L,
            )
            return
        }

        handler.postDelayed(
            {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            },
            3500L,
        )
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
                logDiagnostic("info", "refresh", summary, nowMillis)
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
        synchronized(ttsLock) {
            if (textToSpeech != null) {
                if (!ttsInitCompleted || ttsReady) {
                    return true
                }
                textToSpeech?.shutdown()
                textToSpeech = null
                ttsReady = false
                ttsInitCompleted = false
                ttsInitializationStarted = false
            }
            if (ttsInitializationStarted) {
                return true
            }
            ttsReady = false
            ttsInitCompleted = false
            ttsInitializationStarted = true
        }
        return runCatching {
            val tts = TextToSpeech(applicationContext, this)
            synchronized(ttsLock) {
                textToSpeech = tts
            }
            true
        }.getOrElse { error ->
            synchronized(ttsLock) {
                ttsInitializationStarted = false
                ttsInitCompleted = true
                ttsReady = false
                ttsLock.notifyAll()
            }
            Log.w(TAG, "Unable to initialize TTS in foreground service", error)
            logDiagnostic(
                "warning",
                "speech",
                "前台服务语音初始化异常：${error.message ?: error.javaClass.simpleName}",
            )
            false
        }
    }

    private fun prewarmTtsIfEnabled() {
        if (!loadSettings().soundEnabled) {
            logDiagnostic("info", "speech", "语音播报已关闭，跳过前台服务预热。")
            return
        }
        handler.post {
            val initialized = ensureTts()
            if (!initialized) {
                logDiagnostic("warning", "speech", "前台服务语音预热未能启动。")
            }
        }
    }

    private fun speak(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) {
            return false
        }
        if (!awaitTtsReady()) {
            Log.w(TAG, "Foreground service TTS not ready; skipping speech")
            logDiagnostic("warning", "speech", "语音引擎未就绪，跳过播报。")
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
            logDiagnostic("warning", "speech", "语音播报请求未被系统接受。")
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val preferredVoice = selectPreferredChineseVoice(tts.voices.orEmpty())
            if (preferredVoice != null) {
                val result = tts.setVoice(preferredVoice)
                if (result != TextToSpeech.ERROR) {
                    Log.i(
                        TAG,
                        "Foreground service selected TTS voice: name=${preferredVoice.name}, locale=${preferredVoice.locale}, quality=${preferredVoice.quality}, latency=${preferredVoice.latency}",
                    )
                    return true
                }
            }
        }
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

    private fun selectPreferredChineseVoice(voices: Set<Voice>): Voice? {
        var bestVoice: Voice? = null
        var bestScore = Int.MIN_VALUE
        for (voice in voices) {
            val locale = voice.locale ?: continue
            if (!isChineseLocale(locale)) {
                continue
            }
            if (voice.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)) {
                continue
            }
            val score =
                voice.quality * 1000 -
                    voice.latency * 10 -
                    if (voice.isNetworkConnectionRequired) 3000 else 0
            if (score > bestScore) {
                bestScore = score
                bestVoice = voice
            }
        }
        return bestVoice
    }

    private fun isChineseLocale(locale: Locale): Boolean {
        return locale.language.equals("zh", ignoreCase = true)
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

    private fun logDiagnostic(
        level: String,
        category: String,
        message: String,
        timestampMillis: Long = System.currentTimeMillis(),
    ) {
        runCatching {
            MonitorStorage.appendDiagnosticLog(
                context = this,
                level = level,
                category = category,
                message = message,
                timestampMillis = timestampMillis,
            )
        }.onFailure { error ->
            Log.w(TAG, "Unable to append diagnostic log", error)
        }
    }

    private fun buildAlertNotificationTitle(quote: NativeQuote): String {
        val name = quote.name.trim()
        return if (name.isNotEmpty() && name != quote.code) {
            "$name ${quote.code}"
        } else {
            quote.code
        }
    }

    companion object {
        private const val CHANNEL_ID = "stock_monitor_guard"
        private const val CHANNEL_NAME = "股票异动后台监控"
        private const val NOTIFICATION_ID = 20031
        private const val TAG = "MonitorForegroundSvc"
        const val ACTION_START_MONITOR = "com.stockpulse.radar.action.START_MONITOR"
        const val ACTION_REFRESH_NOW = "com.stockpulse.radar.action.REFRESH_NOW"
        const val ACTION_RELOAD_MONITOR = "com.stockpulse.radar.action.RELOAD_MONITOR"
        const val ACTION_STOP_MONITOR = "com.stockpulse.radar.action.STOP_MONITOR"
        const val ACTION_TEST_ALERT = "com.stockpulse.radar.action.TEST_ALERT"

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

        private fun testAlertSummary(): String = "正在执行后台提醒链路测试。"

        private fun summaryArgument(): String = "summary"

        private fun testAlertNotificationId(timestampMillis: Long): Int {
            return ("background-alert-test:$timestampMillis").hashCode() and Int.MAX_VALUE
        }
    }
}
