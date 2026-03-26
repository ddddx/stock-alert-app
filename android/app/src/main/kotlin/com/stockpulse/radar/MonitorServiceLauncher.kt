package com.stockpulse.radar

import android.content.Context
import android.content.Intent
import android.os.Build

object MonitorServiceLauncher {
    fun startMonitorService(
        context: Context,
        action: String,
        summary: String? = null,
        disableOnFailure: Boolean = false,
        failurePrefix: String = "后台监控启动失败",
    ): Boolean {
        val intent = Intent(context, MonitorForegroundService::class.java).apply {
            this.action = action
            if (!summary.isNullOrBlank()) {
                putExtra("summary", summary)
            }
        }
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            true
        }.getOrElse { error ->
            if (disableOnFailure) {
                MonitorStorage.disableService(
                    context = context,
                    message = "$failurePrefix：${error.safeMessage()}；已自动关闭后台监控，请重新打开应用后再尝试。",
                )
            }
            false
        }
    }

    fun stopMonitorService(context: Context): Boolean {
        val stopIntent = Intent(context, MonitorForegroundService::class.java).apply {
            action = MonitorForegroundService.ACTION_STOP_MONITOR
        }
        return runCatching {
            context.startService(stopIntent)
            true
        }.getOrElse {
            false
        }
    }

    private fun Throwable.safeMessage(): String {
        return when {
            this is SecurityException -> message ?: "缺少前台服务权限"
            isForegroundServiceStartNotAllowed() ->
                message ?: "当前系统状态不允许启动前台服务"
            else -> message ?: javaClass.simpleName
        }
    }

    private fun Throwable.isForegroundServiceStartNotAllowed(): Boolean {
        return javaClass.name == "android.app.ForegroundServiceStartNotAllowedException"
    }
}
