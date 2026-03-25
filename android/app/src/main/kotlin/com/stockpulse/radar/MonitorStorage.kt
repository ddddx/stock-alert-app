package com.stockpulse.radar

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

data class NativeMonitorSettings(
    val serviceEnabled: Boolean,
    val soundEnabled: Boolean,
    val pollIntervalSeconds: Int,
    val lastMessage: String,
)

data class NativeStock(
    val code: String,
    val name: String,
    val market: String,
) {
    val secId: String
        get() = "${if (market == "SH") "1" else "0"}.$code"
}

data class NativeQuote(
    val code: String,
    val name: String,
    val market: String,
    val lastPrice: Double,
    val previousClose: Double,
    val changeAmount: Double,
    val changePercent: Double,
    val openPrice: Double,
    val highPrice: Double,
    val lowPrice: Double,
    val volume: Double,
    val timestampMillis: Long,
)

data class NativeRule(
    val id: String,
    val stockCode: String,
    val stockName: String,
    val market: String,
    val type: String,
    val enabled: Boolean,
    val moveThresholdPercent: Double?,
    val lookbackMinutes: Int?,
    val moveDirection: String?,
    val stepValue: Double?,
    val stepMetric: String?,
    val anchorPrice: Double?,
)

data class NativeRuleState(
    val active: Boolean = false,
    val lastStepIndex: Int? = null,
    val lastTriggeredAtMillis: Long? = null,
)

data class NativeRuntimeState(
    val quoteHistoryByCode: MutableMap<String, MutableList<NativeQuote>> = mutableMapOf(),
    val ruleStates: MutableMap<String, NativeRuleState> = mutableMapOf(),
)

data class NativeAlertHistoryEntry(
    val id: String,
    val ruleId: String,
    val ruleType: String,
    val stockCode: String,
    val stockName: String,
    val market: String,
    val triggeredAtIso: String,
    val currentPrice: Double,
    val referencePrice: Double,
    val changeAmount: Double,
    val changePercent: Double,
    val message: String,
    val spokenText: String,
    val playedSound: Boolean,
)

object MonitorStorage {
    private const val STORAGE_FOLDER = "stock_pulse_data"
    private const val SETTINGS_FILE = "monitor_settings.json"
    private const val WATCHLIST_FILE = "watchlist.json"
    private const val RULES_FILE = "alert_rules.json"
    private const val HISTORY_FILE = "alert_history.json"
    private const val RUNTIME_FILE = "monitor_runtime_state.json"
    private const val DEFAULT_MESSAGE = "等待首次刷新 A 股行情。"

    fun loadSettings(context: Context): NativeMonitorSettings {
        val file = storageFile(context, SETTINGS_FILE)
        val json = readJsonObject(file)
        val interval = (json?.optInt("pollIntervalSeconds", 20) ?: 20).coerceIn(15, 300)
        return NativeMonitorSettings(
            serviceEnabled = json?.optBoolean("serviceEnabled", false) ?: false,
            soundEnabled = json?.optBoolean("soundEnabled", true) ?: true,
            pollIntervalSeconds = interval,
            lastMessage = json?.optString("lastMessage", DEFAULT_MESSAGE).orEmpty().ifBlank {
                DEFAULT_MESSAGE
            },
        )
    }

    fun isServiceEnabled(context: Context): Boolean = loadSettings(context).serviceEnabled

    fun updateStatus(context: Context, checkedAtMillis: Long, message: String) {
        val file = storageFile(context, SETTINGS_FILE)
        val current = readJsonObject(file) ?: JSONObject()
        if (!current.has("serviceEnabled")) {
            current.put("serviceEnabled", false)
        }
        if (!current.has("soundEnabled")) {
            current.put("soundEnabled", true)
        }
        if (!current.has("pollIntervalSeconds")) {
            current.put("pollIntervalSeconds", 20)
        }
        current.put("lastCheckAt", formatIso8601(checkedAtMillis))
        current.put("lastMessage", message.ifBlank { DEFAULT_MESSAGE })
        writeJsonObject(file, current)
    }

    fun loadWatchlist(context: Context): List<NativeStock> {
        val array = readJsonArray(storageFile(context, WATCHLIST_FILE)) ?: return emptyList()
        val stocks = mutableListOf<NativeStock>()
        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            val code = item.optString("code").orEmpty().trim()
            if (code.isEmpty()) {
                continue
            }
            stocks += NativeStock(
                code = code,
                name = item.optString("name").orEmpty().trim(),
                market = item.optString("market", "SZ").orEmpty().trim().ifBlank { "SZ" },
            )
        }
        return stocks
    }

    fun loadRules(context: Context): List<NativeRule> {
        val array = readJsonArray(storageFile(context, RULES_FILE)) ?: return emptyList()
        val rules = mutableListOf<NativeRule>()
        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            val id = item.optString("id").orEmpty().trim()
            if (id.isEmpty()) {
                continue
            }
            rules += NativeRule(
                id = id,
                stockCode = item.optString("stockCode").orEmpty().trim(),
                stockName = item.optString("stockName").orEmpty().trim(),
                market = item.optString("market", "SZ").orEmpty().trim().ifBlank { "SZ" },
                type = item.optString("type", "shortWindowMove").orEmpty().trim(),
                enabled = item.optBoolean("enabled", true),
                moveThresholdPercent = item.optNullableDouble("moveThresholdPercent"),
                lookbackMinutes = item.optNullableInt("lookbackMinutes"),
                moveDirection = item.optNullableString("moveDirection"),
                stepValue = item.optNullableDouble("stepValue"),
                stepMetric = item.optNullableString("stepMetric"),
                anchorPrice = item.optNullableDouble("anchorPrice"),
            )
        }
        return rules
    }

    fun loadRuntimeState(context: Context): NativeRuntimeState {
        val json = readJsonObject(storageFile(context, RUNTIME_FILE)) ?: return NativeRuntimeState()
        val historyByCode = mutableMapOf<String, MutableList<NativeQuote>>()
        val historyJson = json.optJSONObject("quoteHistoryByCode")
        if (historyJson != null) {
            val keys = historyJson.keys()
            while (keys.hasNext()) {
                val code = keys.next()
                val items = historyJson.optJSONArray(code) ?: continue
                val parsed = mutableListOf<NativeQuote>()
                for (index in 0 until items.length()) {
                    val item = items.optJSONObject(index) ?: continue
                    parsed += item.toNativeQuote()
                }
                historyByCode[code] = parsed
            }
        }

        val ruleStates = mutableMapOf<String, NativeRuleState>()
        val statesJson = json.optJSONObject("ruleStates")
        if (statesJson != null) {
            val keys = statesJson.keys()
            while (keys.hasNext()) {
                val ruleId = keys.next()
                val item = statesJson.optJSONObject(ruleId) ?: continue
                ruleStates[ruleId] = NativeRuleState(
                    active = item.optBoolean("active", false),
                    lastStepIndex = item.optNullableInt("lastStepIndex"),
                    lastTriggeredAtMillis = item.optNullableLong("lastTriggeredAtMillis"),
                )
            }
        }

        return NativeRuntimeState(
            quoteHistoryByCode = historyByCode,
            ruleStates = ruleStates,
        )
    }

    fun saveRuntimeState(context: Context, runtimeState: NativeRuntimeState) {
        val root = JSONObject()
        val historyByCode = JSONObject()
        runtimeState.quoteHistoryByCode.forEach { (code, quotes) ->
            val array = JSONArray()
            quotes.sortedBy { it.timestampMillis }.forEach { quote ->
                array.put(
                    JSONObject()
                        .put("code", quote.code)
                        .put("name", quote.name)
                        .put("market", quote.market)
                        .put("lastPrice", quote.lastPrice)
                        .put("previousClose", quote.previousClose)
                        .put("changeAmount", quote.changeAmount)
                        .put("changePercent", quote.changePercent)
                        .put("openPrice", quote.openPrice)
                        .put("highPrice", quote.highPrice)
                        .put("lowPrice", quote.lowPrice)
                        .put("volume", quote.volume)
                        .put("timestampMillis", quote.timestampMillis),
                )
            }
            historyByCode.put(code, array)
        }
        root.put("quoteHistoryByCode", historyByCode)

        val ruleStates = JSONObject()
        runtimeState.ruleStates.forEach { (ruleId, state) ->
            val json = JSONObject()
                .put("active", state.active)
                .put("lastTriggeredAtMillis", state.lastTriggeredAtMillis ?: JSONObject.NULL)
                .put("lastStepIndex", state.lastStepIndex ?: JSONObject.NULL)
            ruleStates.put(ruleId, json)
        }
        root.put("ruleStates", ruleStates)
        writeJsonObject(storageFile(context, RUNTIME_FILE), root)
    }

    fun appendHistoryEntries(context: Context, entries: List<NativeAlertHistoryEntry>) {
        if (entries.isEmpty()) {
            return
        }

        val existing = readJsonArray(storageFile(context, HISTORY_FILE)) ?: JSONArray()
        val merged = JSONArray()
        entries.forEach { entry ->
            merged.put(
                JSONObject()
                    .put("id", entry.id)
                    .put("ruleId", entry.ruleId)
                    .put("ruleType", entry.ruleType)
                    .put("stockCode", entry.stockCode)
                    .put("stockName", entry.stockName)
                    .put("market", entry.market)
                    .put("triggeredAt", entry.triggeredAtIso)
                    .put("currentPrice", entry.currentPrice)
                    .put("referencePrice", entry.referencePrice)
                    .put("changeAmount", entry.changeAmount)
                    .put("changePercent", entry.changePercent)
                    .put("message", entry.message)
                    .put("spokenText", entry.spokenText)
                    .put("playedSound", entry.playedSound),
            )
        }

        for (index in 0 until existing.length()) {
            if (merged.length() >= 100) {
                break
            }
            merged.put(existing.opt(index))
        }
        writeJsonArray(storageFile(context, HISTORY_FILE), merged)
    }

    fun storageDirectory(context: Context): File {
        val directory = File(context.filesDir, STORAGE_FOLDER)
        if (!directory.exists()) {
            directory.mkdirs()
        }
        return directory
    }

    private fun storageFile(context: Context, fileName: String): File {
        return File(storageDirectory(context), fileName)
    }

    private fun readJsonObject(file: File): JSONObject? {
        if (!file.exists()) {
            return null
        }
        val content = file.readText().trim()
        if (content.isEmpty()) {
            return null
        }
        return runCatching { JSONObject(content) }.getOrNull()
    }

    private fun readJsonArray(file: File): JSONArray? {
        if (!file.exists()) {
            return null
        }
        val content = file.readText().trim()
        if (content.isEmpty()) {
            return null
        }
        return runCatching { JSONArray(content) }.getOrNull()
    }

    private fun writeJsonObject(file: File, json: JSONObject) {
        file.writeText(json.toString(2))
    }

    private fun writeJsonArray(file: File, json: JSONArray) {
        file.writeText(json.toString(2))
    }

    fun formatIso8601(timestampMillis: Long): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        formatter.timeZone = TimeZone.getTimeZone("UTC")
        return formatter.format(Date(timestampMillis))
    }

    private fun JSONObject.optNullableString(key: String): String? {
        if (isNull(key) || !has(key)) {
            return null
        }
        return optString(key).orEmpty().trim().ifEmpty { null }
    }

    private fun JSONObject.optNullableDouble(key: String): Double? {
        if (isNull(key) || !has(key)) {
            return null
        }
        return when (val value = opt(key)) {
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull()
            else -> null
        }
    }

    private fun JSONObject.optNullableInt(key: String): Int? {
        if (isNull(key) || !has(key)) {
            return null
        }
        return when (val value = opt(key)) {
            is Number -> value.toInt()
            is String -> value.toIntOrNull()
            else -> null
        }
    }

    private fun JSONObject.optNullableLong(key: String): Long? {
        if (isNull(key) || !has(key)) {
            return null
        }
        return when (val value = opt(key)) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull()
            else -> null
        }
    }

    private fun JSONObject.toNativeQuote(): NativeQuote {
        return NativeQuote(
            code = optString("code").orEmpty(),
            name = optString("name").orEmpty(),
            market = optString("market", "SZ").orEmpty().ifBlank { "SZ" },
            lastPrice = optNumber("lastPrice"),
            previousClose = optNumber("previousClose"),
            changeAmount = optNumber("changeAmount"),
            changePercent = optNumber("changePercent"),
            openPrice = optNumber("openPrice"),
            highPrice = optNumber("highPrice"),
            lowPrice = optNumber("lowPrice"),
            volume = optNumber("volume"),
            timestampMillis = optNullableLong("timestampMillis") ?: System.currentTimeMillis(),
        )
    }

    private fun JSONObject.optNumber(key: String): Double {
        if (isNull(key) || !has(key)) {
            return 0.0
        }
        return when (val value = opt(key)) {
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull() ?: 0.0
            else -> 0.0
        }
    }
}
