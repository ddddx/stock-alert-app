package com.stockpulse.radar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) {
            return
        }
        if (!MonitorStorage.isServiceEnabled(context)) {
            return
        }

        val serviceIntent = Intent(context, MonitorForegroundService::class.java).apply {
            this.action = MonitorForegroundService.ACTION_RELOAD_MONITOR
            putExtra("summary", "设备已重启，后台监控守护已恢复。")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
