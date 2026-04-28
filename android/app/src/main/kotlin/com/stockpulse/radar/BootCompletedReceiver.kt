package com.stockpulse.radar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) {
            return
        }
        if (!MonitorStorage.isServiceEnabled(context)) {
            return
        }

        val summary = when (action) {
            Intent.ACTION_BOOT_COMPLETED -> "检测到设备重启，后台守护正在自动恢复。"
            Intent.ACTION_MY_PACKAGE_REPLACED -> "应用更新完成，后台守护正在自动恢复。"
            else -> "后台守护正在自动恢复。"
        }
        val restored = MonitorServiceLauncher.startMonitorService(
            context = context,
            action = MonitorForegroundService.ACTION_RELOAD_MONITOR,
            summary = summary,
            disableOnFailure = true,
            failurePrefix = "后台守护自动恢复失败",
        )
        if (!restored) {
            return
        }
        MonitorStorage.updateStatus(
            context = context,
            checkedAtMillis = System.currentTimeMillis(),
            message = when (action) {
                Intent.ACTION_BOOT_COMPLETED -> "检测到设备重启，后台守护已自动恢复。"
                Intent.ACTION_MY_PACKAGE_REPLACED -> "应用更新完成，后台守护已自动恢复。"
                else -> "后台守护已自动恢复。"
            },
        )
    }
}
