package com.stockpulse.radar

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var notificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

                    pauseForegroundServiceMethod() -> {
                        val started = MonitorServiceLauncher.startMonitorService(
                            context = this,
                            action = MonitorForegroundService.ACTION_PAUSE_MONITOR,
                            disableOnFailure = false,
                        )
                        result.success(started)
                    }

                    resumeForegroundServiceMethod() -> {
                        val started = MonitorServiceLauncher.startMonitorService(
                            context = this,
                            action = MonitorForegroundService.ACTION_RESUME_MONITOR,
                            disableOnFailure = true,
                            failurePrefix = "后台监控恢复失败",
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
        notificationPermissionResult?.success(false)
        notificationPermissionResult = null
        super.onDestroy()
    }

    private fun openBatteryOptimizationSettings() {
        val powerManager = getSystemService(PowerManager::class.java)
        val packageName = packageName
        val intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && powerManager != null &&
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
        val intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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

    private fun platformChannelName(): String = "stock_pulse/platform"

    private fun summaryArgument(): String = "summary"

    private fun getStorageDirectoryMethod(): String = "getStorageDirectoryPath"

    private fun startForegroundServiceMethod(): String = "startForegroundMonitorService"

    private fun updateForegroundServiceMethod(): String = "updateForegroundMonitorSummary"

    private fun androidBackgroundAccessStatusMethod(): String =
        "getAndroidBackgroundAccessStatus"

    private fun requestNotificationPermissionMethod(): String =
        "requestNotificationPermission"

    private fun reloadForegroundServiceMethod(): String = "reloadForegroundMonitorService"

    private fun refreshForegroundServiceMethod(): String = "refreshForegroundMonitorService"

    private fun pauseForegroundServiceMethod(): String = "pauseForegroundMonitorService"

    private fun resumeForegroundServiceMethod(): String = "resumeForegroundMonitorService"

    private fun stopForegroundServiceMethod(): String = "stopForegroundMonitorService"

    private fun openBatterySettingsMethod(): String = "openBatteryOptimizationSettings"

    private fun openNotificationSettingsMethod(): String = "openNotificationSettings"

    private fun notificationPermissionRequestCode(): Int = 21031
}
