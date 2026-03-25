package com.stockpulse.radar

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

data class NativeAlertTrigger(
    val rule: NativeRule,
    val quote: NativeQuote,
    val triggeredAtMillis: Long,
    val referencePrice: Double,
    val changeAmount: Double,
    val changePercent: Double,
    val message: String,
    val spokenText: String,
)

data class NativeRefreshResult(
    val quotes: List<NativeQuote>,
    val triggers: List<NativeAlertTrigger>,
    val summary: String,
    val checkedAtMillis: Long,
    val error: String? = null,
) {
    val hasError: Boolean
        get() = !error.isNullOrBlank()
}

class NativeMonitorEngine {
    private val marketDataSource = NativeMarketDataSource()

    fun refresh(
        watchlist: List<NativeStock>,
        rules: List<NativeRule>,
        runtimeState: NativeRuntimeState,
        nowMillis: Long = System.currentTimeMillis(),
    ): NativeRefreshResult {
        if (watchlist.isEmpty()) {
            return NativeRefreshResult(
                quotes = emptyList(),
                triggers = emptyList(),
                summary = "自选为空，未执行行情刷新。",
                checkedAtMillis = nowMillis,
            )
        }

        return try {
            val quotes = marketDataSource.fetchQuotes(watchlist)
            quotes.forEach { appendHistory(runtimeState, it) }
            val triggers = evaluateRules(rules, quotes, runtimeState, nowMillis)
            val summary = if (triggers.isEmpty()) {
                "已刷新 ${quotes.size} 只 A 股，暂无规则触发。"
            } else {
                "已刷新 ${quotes.size} 只 A 股，触发 ${triggers.size} 条提醒。"
            }
            NativeRefreshResult(
                quotes = quotes,
                triggers = triggers,
                summary = summary,
                checkedAtMillis = nowMillis,
            )
        } catch (error: Exception) {
            NativeRefreshResult(
                quotes = emptyList(),
                triggers = emptyList(),
                summary = "行情刷新失败：${error.message ?: error.javaClass.simpleName}",
                checkedAtMillis = nowMillis,
                error = error.message ?: error.javaClass.simpleName,
            )
        }
    }

    private fun appendHistory(runtimeState: NativeRuntimeState, quote: NativeQuote) {
        val history = runtimeState.quoteHistoryByCode.getOrPut(quote.code) { mutableListOf() }
        history += quote
        val cutoff = quote.timestampMillis - 2 * 60 * 60 * 1000L
        history.removeAll { it.timestampMillis < cutoff }
        history.sortBy { it.timestampMillis }
    }

    private fun evaluateRules(
        rules: List<NativeRule>,
        quotes: List<NativeQuote>,
        runtimeState: NativeRuntimeState,
        nowMillis: Long,
    ): List<NativeAlertTrigger> {
        val quoteByCode = quotes.associateBy { it.code }
        val triggers = mutableListOf<NativeAlertTrigger>()

        for (rule in rules.filter { it.enabled }) {
            val quote = quoteByCode[rule.stockCode] ?: continue
            val state = runtimeState.ruleStates[rule.id] ?: NativeRuleState()
            when (rule.type) {
                "shortWindowMove" -> {
                    val result = evaluateShortWindowRule(rule, quote, state, runtimeState, nowMillis)
                    runtimeState.ruleStates[rule.id] = result.first
                    result.second?.let(triggers::add)
                }

                "stepAlert" -> {
                    val result = evaluateStepRule(rule, quote, state, nowMillis)
                    runtimeState.ruleStates[rule.id] = result.first
                    result.second?.let(triggers::add)
                }
            }
        }

        return triggers
    }

    private fun evaluateShortWindowRule(
        rule: NativeRule,
        current: NativeQuote,
        state: NativeRuleState,
        runtimeState: NativeRuntimeState,
        nowMillis: Long,
    ): Pair<NativeRuleState, NativeAlertTrigger?> {
        val history = runtimeState.quoteHistoryByCode[current.code].orEmpty()
        val lookbackMinutes = rule.lookbackMinutes ?: 0
        if (lookbackMinutes <= 0 || history.size < 2) {
            return state.copy(active = false) to null
        }

        val cutoff = current.timestampMillis - lookbackMinutes * 60_000L
        val window = history.filter { it.timestampMillis >= cutoff }
        if (window.size < 2) {
            return state.copy(active = false) to null
        }

        val reference = window.first()
        if (reference.lastPrice <= 0) {
            return state.copy(active = false) to null
        }

        val changeAmount = current.lastPrice - reference.lastPrice
        val changePercent = changeAmount / reference.lastPrice * 100.0
        val threshold = rule.moveThresholdPercent ?: 0.0
        val matches = when (rule.moveDirection ?: "either") {
            "up" -> changePercent >= threshold
            "down" -> changePercent <= -threshold
            else -> abs(changePercent) >= threshold
        }

        if (!matches) {
            return state.copy(active = false) to null
        }

        if (state.active) {
            return state.copy(active = true) to null
        }

        val message = buildShortWindowMessage(rule, current, changeAmount, changePercent)
        return state.copy(active = true, lastTriggeredAtMillis = nowMillis) to NativeAlertTrigger(
            rule = rule,
            quote = current,
            triggeredAtMillis = nowMillis,
            referencePrice = reference.lastPrice,
            changeAmount = changeAmount,
            changePercent = changePercent,
            message = message,
            spokenText = message,
        )
    }

    private fun evaluateStepRule(
        rule: NativeRule,
        current: NativeQuote,
        state: NativeRuleState,
        nowMillis: Long,
    ): Pair<NativeRuleState, NativeAlertTrigger?> {
        val stepValue = rule.stepValue ?: 0.0
        if (stepValue <= 0.0) {
            return state to null
        }

        val currentIndex = stepIndex(rule, current)
        if (state.lastStepIndex == null) {
            return state.copy(lastStepIndex = currentIndex, active = false) to null
        }

        if (currentIndex == state.lastStepIndex) {
            return state.copy(active = false) to null
        }

        val referenceValue = if (rule.stepMetric == "percent") current.previousClose else (rule.anchorPrice ?: current.lastPrice)
        val previousIndex = state.lastStepIndex
        val crossedAmount = current.lastPrice - referenceValue
        val crossedPercent = if (referenceValue == 0.0) 0.0 else crossedAmount / referenceValue * 100.0
        val message = buildStepAlertMessage(
            rule = rule,
            current = current,
            previousIndex = previousIndex,
            currentIndex = currentIndex,
            referenceValue = referenceValue,
            crossedAmount = crossedAmount,
            crossedPercent = crossedPercent,
        )

        return state.copy(
            active = true,
            lastStepIndex = currentIndex,
            lastTriggeredAtMillis = nowMillis,
        ) to NativeAlertTrigger(
            rule = rule,
            quote = current,
            triggeredAtMillis = nowMillis,
            referencePrice = referenceValue,
            changeAmount = crossedAmount,
            changePercent = crossedPercent,
            message = message,
            spokenText = message,
        )
    }

    private fun stepIndex(rule: NativeRule, quote: NativeQuote): Int {
        val stepValue = rule.stepValue ?: return 0
        if (stepValue <= 0.0) {
            return 0
        }
        return if (rule.stepMetric == "percent") {
            bandIndex(quote.changePercent / stepValue)
        } else {
            val anchor = rule.anchorPrice ?: quote.lastPrice
            bandIndex((quote.lastPrice - anchor) / stepValue)
        }
    }

    private fun bandIndex(value: Double): Int {
        return if (value >= 0.0) floor(value).toInt() else ceil(value).toInt()
    }

    private fun buildShortWindowMessage(
        rule: NativeRule,
        current: NativeQuote,
        changeAmount: Double,
        changePercent: Double,
    ): String {
        val direction = if (changeAmount >= 0) "上涨" else "下跌"
        return "${current.name}(${current.code}) ${rule.lookbackMinutes} 分钟内$direction${formatAbsPercent(changePercent)}，变动 ${formatSignedPrice(changeAmount)}，现价 ${formatPrice(current.lastPrice)}。"
    }

    private fun buildStepAlertMessage(
        rule: NativeRule,
        current: NativeQuote,
        previousIndex: Int,
        currentIndex: Int,
        referenceValue: Double,
        crossedAmount: Double,
        crossedPercent: Double,
    ): String {
        return if (rule.stepMetric == "percent") {
            "${current.name}(${current.code}) 涨跌幅跨过 ${String.format(Locale.US, "%.2f", currentIndex * (rule.stepValue ?: 0.0))}% 台阶，本次累计波动 ${formatSignedPrice(crossedAmount)}，累计涨跌幅 ${formatPercent(crossedPercent)}，当前涨跌幅 ${formatPercent(current.changePercent)}，现价 ${formatPrice(current.lastPrice)}。"
        } else {
            val stepValue = rule.stepValue ?: 0.0
            "${current.name}(${current.code}) 价格从 ${formatPrice(referenceValue + previousIndex * stepValue)} 跨到 ${formatPrice(referenceValue + currentIndex * stepValue)} 台阶，本次累计波动 ${formatSignedPrice(crossedAmount)}，累计涨跌幅 ${formatPercent(crossedPercent)}，当前价格 ${formatPrice(current.lastPrice)}。"
        }
    }

    private fun formatPrice(value: Double): String = "¥${String.format(Locale.US, "%.2f", value)}"

    private fun formatSignedPrice(value: Double): String {
        val sign = if (value > 0) "+" else if (value < 0) "-" else ""
        return "$sign¥${String.format(Locale.US, "%.2f", abs(value))}"
    }

    private fun formatPercent(value: Double): String {
        val sign = if (value > 0) "+" else if (value < 0) "-" else ""
        return "$sign${String.format(Locale.US, "%.2f", abs(value))}%"
    }

    private fun formatAbsPercent(value: Double): String = "${String.format(Locale.US, "%.2f", abs(value))}%"
}

class NativeMarketDataSource {
    fun fetchQuotes(stocks: List<NativeStock>): List<NativeQuote> {
        return stocks.map { fetchSingleQuote(it) }
    }

    private fun fetchSingleQuote(stock: NativeStock): NativeQuote {
        val url = URL(
            "https://push2.eastmoney.com/api/qt/stock/get" +
                "?invt=2&fltt=2&secid=${stock.secId}&fields=f57,f58,f43,f169,f170,f46,f44,f45,f47,f48,f60,f18"
        )
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 8000
            readTimeout = 8000
            setRequestProperty("Accept", "application/json, text/plain, */*")
            setRequestProperty("User-Agent", "Mozilla/5.0")
            setRequestProperty("Referer", "https://quote.eastmoney.com/")
        }

        try {
            val status = connection.responseCode
            if (status !in 200..299) {
                throw IllegalStateException("接口请求失败: $status")
            }
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val payload = JSONObject(body)
            val data = payload.optJSONObject("data") ?: throw IllegalStateException("行情接口返回为空")
            val previousClose = scaledNumber(data, "f60").takeIf { it != 0.0 } ?: scaledNumber(data, "f18")
            return NativeQuote(
                code = data.optString("f57").orEmpty().ifBlank { stock.code },
                name = data.optString("f58").orEmpty().ifBlank { stock.name },
                market = stock.market,
                lastPrice = scaledNumber(data, "f43"),
                previousClose = previousClose,
                changeAmount = scaledNumber(data, "f169"),
                changePercent = scaledNumber(data, "f170"),
                openPrice = scaledNumber(data, "f46"),
                highPrice = scaledNumber(data, "f44"),
                lowPrice = scaledNumber(data, "f45"),
                volume = plainNumber(data, "f47"),
                timestampMillis = System.currentTimeMillis(),
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun scaledNumber(json: JSONObject, key: String): Double = plainNumber(json, key) / 100.0

    private fun plainNumber(json: JSONObject, key: String): Double {
        if (!json.has(key) || json.isNull(key)) {
            return 0.0
        }
        val value = json.opt(key)
        return when (value) {
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull() ?: 0.0
            else -> 0.0
        }
    }
}
