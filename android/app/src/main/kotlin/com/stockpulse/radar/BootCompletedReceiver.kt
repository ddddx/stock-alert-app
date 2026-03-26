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

        MonitorStorage.disableService(
            context = context,
            message = when (action) {
                Intent.ACTION_BOOT_COMPLETED -> "检测到设备重启。为兼容部分安卓机型，后台守护不会自动恢复，请打开应用后手动重新开启。"
                Intent.ACTION_MY_PACKAGE_REPLACED -> "应用刚完成更新。为避免升级后冷启动闪退，后台守护已暂时关闭，请打开应用后手动重新开启。"
                else -> "后台守护已关闭，请打开应用后手动重新开启。"
            },
        )
    }
}
