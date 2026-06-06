package com.stockpulse.radar

import android.content.Context
import java.util.Calendar
import java.util.TimeZone

private const val MIN_POLL_INTERVAL_SECONDS = 1
private const val MAX_POLL_INTERVAL_SECONDS = 300
private const val MIN_ALERT_COOLDOWN_SECONDS = 0
private const val MAX_ALERT_COOLDOWN_SECONDS = 3600
private const val MORNING_SESSION_START_MINUTES = 9 * 60 + 30
private const val MORNING_SESSION_END_MINUTES = 11 * 60 + 30
private const val AFTERNOON_SESSION_START_MINUTES = 13 * 60
private const val AFTERNOON_SESSION_END_MINUTES = 15 * 60
private val DEFAULT_ASHARE_CLOSED_DATES = setOf(
    // 2026 A-share holiday closures from SSE/SZSE annual notice.
    "2026-01-01",
    "2026-01-02",
    "2026-02-16",
    "2026-02-17",
    "2026-02-18",
    "2026-02-19",
    "2026-02-20",
    "2026-02-23",
    "2026-04-06",
    "2026-05-01",
    "2026-05-04",
    "2026-05-05",
    "2026-06-19",
    "2026-09-25",
    "2026-10-01",
    "2026-10-02",
    "2026-10-05",
    "2026-10-06",
    "2026-10-07",
)

data class NativeTradingCalendar(
    val closedDates: Set<String> = DEFAULT_ASHARE_CLOSED_DATES,
    val openDates: Set<String> = emptySet(),
)

data class AshareMarketSession(
    val isTradingOpen: Boolean,
    val nextOpenAtMillis: Long,
) {
    fun delayUntilNextOpenMillis(nowMillis: Long): Long {
        return (nextOpenAtMillis - nowMillis).coerceAtLeast(1000L)
    }
}

object AshareMarketSchedule {
    private val chinaTimeZone: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")

    fun normalizePollIntervalSeconds(seconds: Int): Int {
        return seconds.coerceIn(MIN_POLL_INTERVAL_SECONDS, MAX_POLL_INTERVAL_SECONDS)
    }

    fun normalizeAlertCooldownSeconds(seconds: Int): Int {
        return seconds.coerceIn(MIN_ALERT_COOLDOWN_SECONDS, MAX_ALERT_COOLDOWN_SECONDS)
    }

    fun defaultTradingCalendar(): NativeTradingCalendar {
        return NativeTradingCalendar(
            closedDates = DEFAULT_ASHARE_CLOSED_DATES,
            openDates = emptySet(),
        )
    }

    fun currentSession(
        context: Context,
        nowMillis: Long = System.currentTimeMillis(),
    ): AshareMarketSession {
        val tradingCalendar = MonitorStorage.loadTradingCalendar(context)
        val now = Calendar.getInstance(chinaTimeZone).apply {
            timeInMillis = nowMillis
        }
        val minutesSinceMidnight = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val isTradingOpen = isTradingDay(now, tradingCalendar) && (
            (minutesSinceMidnight >= MORNING_SESSION_START_MINUTES && minutesSinceMidnight < MORNING_SESSION_END_MINUTES) ||
                (minutesSinceMidnight >= AFTERNOON_SESSION_START_MINUTES && minutesSinceMidnight < AFTERNOON_SESSION_END_MINUTES)
            )
        val nextOpenAtMillis = nextOpenAt(now, tradingCalendar).timeInMillis
        return AshareMarketSession(
            isTradingOpen = isTradingOpen,
            nextOpenAtMillis = nextOpenAtMillis,
        )
    }

    fun buildClosedSummary(session: AshareMarketSession): String {
        val next = Calendar.getInstance(chinaTimeZone).apply {
            timeInMillis = session.nextOpenAtMillis
        }
        return "当前不在 A 股交易时段，后台监控已暂停，将于${formatSessionLabel(next)}恢复。"
    }

    private fun nextOpenAt(
        reference: Calendar,
        tradingCalendar: NativeTradingCalendar,
    ): Calendar {
        val next = (reference.clone() as Calendar).apply {
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val minutesSinceMidnight = next.get(Calendar.HOUR_OF_DAY) * 60 + next.get(Calendar.MINUTE)

        if (!isTradingDay(next, tradingCalendar)) {
            return moveToNextOpenMorning(next, tradingCalendar)
        }
        if (minutesSinceMidnight < MORNING_SESSION_START_MINUTES) {
            return setSessionStart(next, hour = 9, minute = 30)
        }
        if (minutesSinceMidnight < MORNING_SESSION_END_MINUTES) {
            return next
        }
        if (minutesSinceMidnight < AFTERNOON_SESSION_START_MINUTES) {
            return setSessionStart(next, hour = 13, minute = 0)
        }
        if (minutesSinceMidnight < AFTERNOON_SESSION_END_MINUTES) {
            return next
        }

        next.add(Calendar.DAY_OF_MONTH, 1)
        return moveToNextOpenMorning(next, tradingCalendar)
    }

    private fun moveToNextOpenMorning(
        calendar: Calendar,
        tradingCalendar: NativeTradingCalendar,
    ): Calendar {
        while (!isTradingDay(calendar, tradingCalendar)) {
            calendar.add(Calendar.DAY_OF_MONTH, 1)
        }
        return setSessionStart(calendar, hour = 9, minute = 30)
    }

    private fun isTradingDay(
        calendar: Calendar,
        tradingCalendar: NativeTradingCalendar,
    ): Boolean {
        val dateKey = dateKey(calendar)
        if (tradingCalendar.openDates.contains(dateKey)) {
            return true
        }
        if (tradingCalendar.closedDates.contains(dateKey)) {
            return false
        }
        val weekday = calendar.get(Calendar.DAY_OF_WEEK)
        return weekday != Calendar.SATURDAY && weekday != Calendar.SUNDAY
    }

    fun dateKey(calendar: Calendar): String {
        return "%04d-%02d-%02d".format(
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH) + 1,
            calendar.get(Calendar.DAY_OF_MONTH),
        )
    }

    private fun setSessionStart(calendar: Calendar, hour: Int, minute: Int): Calendar {
        calendar.set(Calendar.HOUR_OF_DAY, hour)
        calendar.set(Calendar.MINUTE, minute)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        return calendar
    }

    private fun formatSessionLabel(calendar: Calendar): String {
        val weekday = when (calendar.get(Calendar.DAY_OF_WEEK)) {
            Calendar.MONDAY -> "周一"
            Calendar.TUESDAY -> "周二"
            Calendar.WEDNESDAY -> "周三"
            Calendar.THURSDAY -> "周四"
            Calendar.FRIDAY -> "周五"
            Calendar.SATURDAY -> "周六"
            Calendar.SUNDAY -> "周日"
            else -> ""
        }
        val month = calendar.get(Calendar.MONTH) + 1
        val day = calendar.get(Calendar.DAY_OF_MONTH)
        val hour = calendar.get(Calendar.HOUR_OF_DAY)
        val minute = calendar.get(Calendar.MINUTE)
        return "%02d-%02d %s %02d:%02d".format(month, day, weekday, hour, minute)
    }
}
