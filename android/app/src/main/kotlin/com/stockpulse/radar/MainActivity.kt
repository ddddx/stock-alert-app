package com.stockpulse.radar

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false
    private var ttsInitCompleted = false
    private val pendingInitResults = mutableListOf<MethodChannel.Result>()
    private val pendingSpeakRequests = mutableListOf<PendingSpeakRequest>()
    private var lastSpeakAttemptStarted = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ttsChannelName())
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    initMethod() -> {
                        if (ttsInitCompleted) {
                            result.success(ttsReady)
                            return@setMethodCallHandler
                        }
                        if (!ensureTts()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        pendingInitResults += result
                    }

                    speakMethod() -> {
                        val text = call.argument<String>(textArgument()).orEmpty().trim()
                        if (text.isEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        if (ttsInitCompleted) {
                            result.success(if (ttsReady) speakNow(text) else false)
                            return@setMethodCallHandler
                        }
                        if (!ensureTts()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        pendingSpeakRequests += PendingSpeakRequest(text, result)
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, platformChannelName())
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    getStorageDirectoryMethod() -> {
                        result.success(MonitorStorage.storageDirectory(this).absolutePath)
                    }

                    startForegroundServiceMethod() -> {
                        val summary = call.argument<String>(summaryArgument()).orEmpty()
                        val started = MonitorServiceLauncher.startMonitorService(
                            context = this,
                            action = MonitorForegroundService.ACTION_START_MONITOR,
                            summary = summary,
                            disableOnFailure = true,
                        )
                        result.success(started)
                    }

                    updateForegroundServiceMethod() -> {
                        val summary = call.argument<String>(summaryArgument()).orEmpty()
                        MonitorForegroundService.updateSummary(this, summary)
                        result.success(true)
                    }

                    reloadForegroundServiceMethod() -> {
                        val started = MonitorServiceLauncher.startMonitorService(
                            context = this,
                            action = MonitorForegroundService.ACTION_RELOAD_MONITOR,
                            disableOnFailure = true,
                            failurePrefix = "后台监控恢复失败",
                        )
                        result.success(started)
                    }

                    refreshForegroundServiceMethod() -> {
                        val started = MonitorServiceLauncher.startMonitorService(
                            context = this,
                            action = MonitorForegroundService.ACTION_REFRESH_NOW,
                            disableOnFailure = true,
                            failurePrefix = "后台监控刷新失败",
                        )
                        result.success(started)
                    }

                    stopForegroundServiceMethod() -> {
                        result.success(MonitorServiceLauncher.stopMonitorService(this))
                    }

                    openBatterySettingsMethod() -> {
                        openBatteryOptimizationSettings()
                        result.success(true)
                    }

                    openNotificationSettingsMethod() -> {
                        openNotificationSettings()
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onInit(status: Int) {
        ttsInitCompleted = true
        ttsReady = status == TextToSpeech.SUCCESS && configureTtsVoice()
        if (ttsReady) {
            textToSpeech?.setSpeechRate(1.0f)
            textToSpeech?.setPitch(1.0f)
        }
        flushPendingTtsRequests()
    }

    override fun onDestroy() {
        failPendingTtsRequests()
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }

    private fun ensureTts(): Boolean {
        if (textToSpeech != null) {
            return true
        }
        return runCatching {
            ttsReady = false
            ttsInitCompleted = false
            textToSpeech = TextToSpeech(applicationContext, this)
            true
        }.getOrElse {
            false
        }
    }

    private fun speakNow(text: String): Boolean {
        if (!ttsReady) {
            return false
        }
        val utteranceId = utterancePrefix() + System.currentTimeMillis()
        val startedSignal = CountDownLatch(1)
        lastSpeakAttemptStarted = false
        textToSpeech?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                lastSpeakAttemptStarted = true
                startedSignal.countDown()
            }

            override fun onDone(utteranceId: String?) {
                startedSignal.countDown()
            }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                startedSignal.countDown()
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                startedSignal.countDown()
            }
        })
        val queued = textToSpeech?.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            utteranceId,
        ) == TextToSpeech.SUCCESS
        if (!queued) {
            return false
        }
        startedSignal.await(1500, TimeUnit.MILLISECONDS)
        return lastSpeakAttemptStarted
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
                    return true
                }
            }
        }
        return false
    }

    private fun flushPendingTtsRequests() {
        val initResults = pendingInitResults.toList()
        pendingInitResults.clear()
        initResults.forEach { it.success(ttsReady) }

        val speakRequests = pendingSpeakRequests.toList()
        pendingSpeakRequests.clear()
        speakRequests.forEach { request ->
            request.result.success(if (ttsReady) speakNow(request.text) else false)
        }
    }

    private fun failPendingTtsRequests() {
        if (pendingInitResults.isEmpty() && pendingSpeakRequests.isEmpty()) {
            return
        }
        ttsReady = false
        ttsInitCompleted = true
        flushPendingTtsRequests()
    }

    private fun openBatteryOptimizationSettings() {
        val powerManager = getSystemService(PowerManager::class.java)
        val packageName = packageName
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && powerManager != null &&
            !powerManager.isIgnoringBatteryOptimizations(packageName)
        ) {
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
        } else {
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun ttsChannelName(): String = "stock_pulse/tts"

    private fun platformChannelName(): String = "stock_pulse/platform"

    private fun initMethod(): String = "initTts"

    private fun speakMethod(): String = "speak"

    private fun textArgument(): String = "text"

    private fun summaryArgument(): String = "summary"

    private fun utterancePrefix(): String = "stock-pulse-"

    private fun getStorageDirectoryMethod(): String = "getStorageDirectoryPath"

    private fun startForegroundServiceMethod(): String = "startForegroundMonitorService"

    private fun updateForegroundServiceMethod(): String = "updateForegroundMonitorSummary"

    private fun reloadForegroundServiceMethod(): String = "reloadForegroundMonitorService"

    private fun refreshForegroundServiceMethod(): String = "refreshForegroundMonitorService"

    private fun stopForegroundServiceMethod(): String = "stopForegroundMonitorService"

    private fun openBatterySettingsMethod(): String = "openBatteryOptimizationSettings"

    private fun openNotificationSettingsMethod(): String = "openNotificationSettings"

    private data class PendingSpeakRequest(
        val text: String,
        val result: MethodChannel.Result,
    )
}
