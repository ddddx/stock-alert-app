package com.stockpulse.radar

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false
    private var ttsInitCompleted = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingInitResults = mutableListOf<MethodChannel.Result>()
    private val pendingSpeakRequests = mutableListOf<PendingSpeakRequest>()
    private val activeUtterances = mutableMapOf<String, ActiveUtterance>()
    private var notificationPermissionResult: MethodChannel.Result? = null

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
                            if (!ttsReady) {
                                result.success(false)
                            } else {
                                speakNow(text, result)
                            }
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

                    androidBackgroundAccessStatusMethod() -> {
                        result.success(buildAndroidBackgroundAccessStatus())
                    }

                    requestNotificationPermissionMethod() -> {
                        requestNotificationPermission(result)
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
            textToSpeech?.setOnUtteranceProgressListener(ttsProgressListener())
        }
        flushPendingTtsRequests()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequestCode()) {
            return
        }

        val granted = hasNotificationPermission()
        notificationPermissionResult?.success(granted)
        notificationPermissionResult = null
    }

    override fun onDestroy() {
        failPendingTtsRequests()
        activeUtterances.keys.toList().forEach { finishUtterance(it, false) }
        notificationPermissionResult?.success(false)
        notificationPermissionResult = null
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

    private fun speakNow(text: String, result: MethodChannel.Result) {
        if (!ttsReady) {
            result.success(false)
            return
        }
        val utteranceId = utterancePrefix() + System.currentTimeMillis()
        val timeoutRunnable = Runnable {
            finishUtterance(utteranceId, false)
        }
        activeUtterances[utteranceId] = ActiveUtterance(result, timeoutRunnable)
        val queued = textToSpeech?.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            utteranceId,
        ) == TextToSpeech.SUCCESS
        if (!queued) {
            finishUtterance(utteranceId, false)
            return
        }
        mainHandler.postDelayed(timeoutRunnable, utteranceTimeoutMillis())
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
            if (!ttsReady) {
                request.result.success(false)
            } else {
                speakNow(request.text, request.result)
            }
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

    private fun buildAndroidBackgroundAccessStatus(): Map<String, Any> {
        val sdkInt = Build.VERSION.SDK_INT
        return mapOf(
            "isAndroid" to true,
            "sdkInt" to sdkInt,
            "notificationsRuntimePermissionRequired" to
                (sdkInt >= Build.VERSION_CODES.TIRAMISU),
            "notificationPermissionGranted" to hasNotificationPermission(),
            "notificationsEnabled" to NotificationManagerCompat.from(this)
                .areNotificationsEnabled(),
            "ignoringBatteryOptimizations" to isIgnoringBatteryOptimizations(),
        )
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
            return
        }
        if (hasNotificationPermission()) {
            result.success(true)
            return
        }
        notificationPermissionResult?.success(false)
        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode(),
        )
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return NotificationManagerCompat.from(this).areNotificationsEnabled()
        }
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        val powerManager = getSystemService(PowerManager::class.java) ?: return true
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }

    private fun ttsProgressListener(): UtteranceProgressListener {
        return object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) = Unit

            override fun onDone(utteranceId: String?) {
                finishUtterance(utteranceId, true)
            }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                finishUtterance(utteranceId, false)
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                finishUtterance(utteranceId, false)
            }

            override fun onStop(utteranceId: String?, interrupted: Boolean) {
                finishUtterance(utteranceId, false)
            }
        }
    }

    private fun finishUtterance(utteranceId: String?, completed: Boolean) {
        if (utteranceId == null) {
            return
        }
        val activeUtterance = activeUtterances.remove(utteranceId) ?: return
        mainHandler.removeCallbacks(activeUtterance.timeoutRunnable)
        runOnUiThread {
            activeUtterance.result.success(completed)
        }
    }

    private fun utteranceTimeoutMillis(): Long = 12000L

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

    private fun androidBackgroundAccessStatusMethod(): String =
        "getAndroidBackgroundAccessStatus"

    private fun requestNotificationPermissionMethod(): String =
        "requestNotificationPermission"

    private fun reloadForegroundServiceMethod(): String = "reloadForegroundMonitorService"

    private fun refreshForegroundServiceMethod(): String = "refreshForegroundMonitorService"

    private fun stopForegroundServiceMethod(): String = "stopForegroundMonitorService"

    private fun openBatterySettingsMethod(): String = "openBatteryOptimizationSettings"

    private fun openNotificationSettingsMethod(): String = "openNotificationSettings"

    private fun notificationPermissionRequestCode(): Int = 21031

    private data class ActiveUtterance(
        val result: MethodChannel.Result,
        val timeoutRunnable: Runnable,
    )

    private data class PendingSpeakRequest(
        val text: String,
        val result: MethodChannel.Result,
    )
}
