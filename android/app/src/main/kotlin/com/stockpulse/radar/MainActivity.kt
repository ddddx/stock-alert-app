package com.stockpulse.radar

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ttsChannelName())
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    initMethod() -> {
                        ensureTts()
                        result.success(true)
                    }

                    speakMethod() -> {
                        val text = call.argument<String>(textArgument()).orEmpty().trim()
                        if (text.isEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        ensureTts()
                        result.success(speak(text))
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, platformChannelName())
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    getStorageDirectoryMethod() -> {
                        val directory = File(filesDir, storageFolderName())
                        if (!directory.exists()) {
                            directory.mkdirs()
                        }
                        result.success(directory.absolutePath)
                    }

                    startForegroundServiceMethod() -> {
                        val summary = call.argument<String>(summaryArgument()).orEmpty()
                        startMonitorService(summary)
                        result.success(true)
                    }

                    updateForegroundServiceMethod() -> {
                        val summary = call.argument<String>(summaryArgument()).orEmpty()
                        MonitorForegroundService.updateSummary(this, summary)
                        result.success(true)
                    }

                    stopForegroundServiceMethod() -> {
                        stopService(Intent(this, MonitorForegroundService::class.java))
                        result.success(true)
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

    override fun onDestroy() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }

    private fun ensureTts() {
        if (textToSpeech == null) {
            textToSpeech = TextToSpeech(this, this)
        }
    }

    private fun speak(text: String): Boolean {
        if (!ttsReady) {
            return false
        }
        return textToSpeech?.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            utterancePrefix() + System.currentTimeMillis()
        ) == TextToSpeech.SUCCESS
    }

    private fun startMonitorService(summary: String) {
        val intent = Intent(this, MonitorForegroundService::class.java).apply {
            action = monitorActionStart()
            putExtra(summaryArgument(), summary)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
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

    private fun stopForegroundServiceMethod(): String = "stopForegroundMonitorService"

    private fun openBatterySettingsMethod(): String = "openBatteryOptimizationSettings"

    private fun openNotificationSettingsMethod(): String = "openNotificationSettings"

    private fun monitorActionStart(): String = "com.stockpulse.radar.action.START_MONITOR"

    private fun storageFolderName(): String = "stock_pulse_data"
}
