package com.stockpulse.radar

import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.util.Locale
import org.json.JSONObject
import kotlin.math.abs

class RobustNativeMarketDataSource(
    private val jsonLoader: ((URL) -> JSONObject)? = null,
    private val textLoader: ((URL) -> String)? = null,
    private val sleeper: (Long) -> Unit = { Thread.sleep(it) },
    private val clock: () -> Long = { System.currentTimeMillis() },
) {
    companion object {
        private const val maxConcurrentQuoteFetches = 4
        private const val eastmoneyQuoteReferer = "https://quote.eastmoney.com/"
        private const val tencentQuoteReferer = "https://qt.gtimg.cn/"
        private val requestRetryBackoffsMillis = listOf(250L, 500L)
        private val tencentQuoteLayouts = listOf(
            NativeTencentQuoteLayout(31, 32, 33, 34, 36),
            NativeTencentQuoteLayout(30, 31, 32, 33, 35),
        )
    }

    fun fetchQuotes(stocks: List<NativeStock>): NativeQuoteFetchResult {
        if (stocks.isEmpty()) {
            return NativeQuoteFetchResult(
                quotes = emptyList(),
                failedCount = 0,
            )
        }

        val quotesByCode = linkedMapOf<String, NativeQuote>()
        var fallbackStocks = stocks

        try {
            val batchResult = fetchBatchQuotes(stocks)
            quotesByCode.putAll(batchResult.quotesByCode)
            fallbackStocks = batchResult.fallbackStocks
        } catch (_: Exception) {
            // Fall back to per-symbol retrieval when batch data is unavailable.
        }

        if (fallbackStocks.isEmpty()) {
            return NativeQuoteFetchResult(
                quotes = stocks.mapNotNull { stock -> quotesByCode[stock.code] },
                failedCount = 0,
            )
        }

        val executor = java.util.concurrent.Executors.newFixedThreadPool(minOf(fallbackStocks.size, maxConcurrentQuoteFetches))
        val futures = fallbackStocks.map { stock ->
            executor.submit<NativeQuoteFetchOutcome> { fetchSingleQuoteOutcome(stock) }
        }

        return try {
            var failedCount = 0
            var lastFailure: NativeQuoteFetchOutcome? = null

            futures.forEach { future ->
                val outcome = future.get()
                val quote = outcome.quote
                if (quote != null) {
                    quotesByCode[quote.code] = quote
                } else {
                    failedCount += 1
                    lastFailure = outcome
                }
            }

            if (quotesByCode.isEmpty() && lastFailure != null) {
                throw lastFailure.error ?: IllegalStateException("行情刷新失败")
            }

            NativeQuoteFetchResult(
                quotes = stocks.mapNotNull { stock -> quotesByCode[stock.code] },
                failedCount = failedCount,
            )
        } catch (error: InterruptedException) {
            futures.forEach { it.cancel(true) }
            Thread.currentThread().interrupt()
            throw IllegalStateException("行情刷新被中断", error)
        } catch (error: java.util.concurrent.ExecutionException) {
            futures.forEach { it.cancel(true) }
            val cause = error.cause
            when (cause) {
                is Exception -> throw cause
                else -> throw IllegalStateException("行情刷新失败", cause ?: error)
            }
        } finally {
            executor.shutdownNow()
        }
    }

    private fun fetchSingleQuoteOutcome(stock: NativeStock): NativeQuoteFetchOutcome {
        return try {
            NativeQuoteFetchOutcome.success(fetchSingleQuote(stock))
        } catch (error: Exception) {
            NativeQuoteFetchOutcome.failure(error)
        }
    }

    private fun fetchSingleQuote(stock: NativeStock): NativeQuote {
        var eastmoneyFailure: Exception? = null

        try {
            val eastmoneyQuote = fetchEastmoneySingleQuote(stock)
            if (isUsableSingleQuote(eastmoneyQuote)) {
                return eastmoneyQuote
            }
            eastmoneyFailure = IllegalStateException("Eastmoney single quote is unusable")
        } catch (error: Exception) {
            eastmoneyFailure = error
        }

        try {
            val tencentQuote = fetchTencentSingleQuote(stock)
            if (isUsableSingleQuote(tencentQuote)) {
                return tencentQuote
            }
        } catch (_: Exception) {
        }

        throw eastmoneyFailure ?: IllegalStateException("行情刷新失败")
    }

    private fun fetchBatchQuotes(stocks: List<NativeStock>): NativeBatchQuoteResult {
        val url = URL(
            "https://push2.eastmoney.com/api/qt/ulist.np/get" +
                "?invt=2&fltt=2" +
                "&fields=f12,f13,f14,f18,f57,f58,f59,f43,f169,f170,f46,f44,f45,f47,f60" +
                "&secids=${stocks.joinToString(",") { it.secId }}",
        )
        val payload = loadJsonWithRetry(url, eastmoneyQuoteReferer)
        val data = payload.optJSONObject("data") ?: throw IllegalStateException("Batch quote payload is empty")
        val diff = data.optJSONArray("diff") ?: throw IllegalStateException("Batch quote list is empty")
        val stockByCode = stocks.associateBy { it.code }
        val quotesByCode = linkedMapOf<String, NativeQuote>()
        val timestampMillis = clock()

        for (index in 0 until diff.length()) {
            val item = diff.optJSONObject(index) ?: continue
            val code = readFirstNonBlankString(item, listOf("f57", "f12"))
            val stock = stockByCode[code] ?: continue
            val quote = tryParseBatchQuote(stock, item, timestampMillis)
            if (quote != null) {
                quotesByCode[stock.code] = quote
            }
        }

        if (quotesByCode.isEmpty()) {
            throw IllegalStateException("Batch quote list resolved to zero quotes")
        }

        return NativeBatchQuoteResult(
            quotesByCode = quotesByCode,
            fallbackStocks = stocks.filter { stock -> !quotesByCode.containsKey(stock.code) },
        )
    }

    private fun tryParseBatchQuote(stock: NativeStock, data: JSONObject, timestampMillis: Long): NativeQuote? {
        if (!hasUsableField(data, listOf("f57", "f12")) ||
            !hasUsableNumber(data, listOf("f43")) ||
            !hasUsableNumber(data, listOf("f169")) ||
            !hasUsableNumber(data, listOf("f170", "f3")) ||
            !hasUsableNumber(data, listOf("f46")) ||
            !hasUsableNumber(data, listOf("f44")) ||
            !hasUsableNumber(data, listOf("f45")) ||
            !hasUsableNumber(data, listOf("f47")) ||
            !hasUsableNumber(data, listOf("f60", "f18"))
        ) {
            return null
        }

        val quote = parseEastmoneyQuote(
            stock = stock,
            data = data,
            timestampMillis = timestampMillis,
            codeKeys = listOf("f57", "f12"),
            previousCloseKeys = listOf("f60", "f18"),
            percentValue = normalizeBatchPercent(stock, data),
        )
        return if (isSaneBatchQuote(quote)) quote else null
    }

    private fun fetchEastmoneySingleQuote(stock: NativeStock): NativeQuote {
        val url = URL(
            "https://push2.eastmoney.com/api/qt/stock/get" +
                "?invt=2&fltt=2&secid=${stock.secId}&fields=f57,f58,f59,f43,f169,f170,f46,f44,f45,f47,f48,f60,f18",
        )
        val payload = loadJsonWithRetry(url, eastmoneyQuoteReferer)
        val data = payload.optJSONObject("data") ?: throw IllegalStateException("行情接口返回为空")
        return parseEastmoneyQuote(
            stock = stock,
            data = data,
            timestampMillis = clock(),
            codeKeys = listOf("f57"),
            previousCloseKeys = listOf("f60", "f18"),
            percentValue = data.opt("f170"),
        )
    }

    private fun fetchTencentSingleQuote(stock: NativeStock): NativeQuote {
        val marketPrefix = if (stock.market.uppercase(Locale.ROOT) == "SH") "sh" else "sz"
        val url = URL("https://qt.gtimg.cn/q=$marketPrefix${stock.code}")
        val payload = loadTextWithRetry(url, "text/plain, */*", tencentQuoteReferer, latin1 = true)
        val fields = parseTencentQuoteFields(payload)
        if (fields.size <= 35) {
            throw IllegalStateException("Tencent quote payload is incomplete")
        }

        for (layout in tencentQuoteLayouts) {
            val quote = tryParseTencentSingleQuote(stock, fields, layout)
            if (quote != null && isUsableSingleQuote(quote)) {
                return quote
            }
        }

        throw IllegalStateException("Tencent quote payload is missing numeric fields")
    }

    private fun tryParseTencentSingleQuote(stock: NativeStock, fields: List<String>, layout: NativeTencentQuoteLayout): NativeQuote? {
        val lastPrice = parseTencentNumber(fields, 3)
        val previousClose = parseTencentNumber(fields, 4)
        val openPrice = parseTencentNumber(fields, 5)
        val highPrice = parseTencentNumber(fields, layout.highPriceIndex)
        val lowPrice = parseTencentNumber(fields, layout.lowPriceIndex)
        val changeAmount = parseTencentNumber(fields, layout.changeAmountIndex)
        val changePercent = parseTencentNumber(fields, layout.changePercentIndex)
        val volume = parseTencentNumber(fields, layout.volumeIndex)

        if (lastPrice == null || previousClose == null || openPrice == null || highPrice == null || lowPrice == null || changeAmount == null || changePercent == null || volume == null) {
            return null
        }

        return NativeQuote(
            code = fields.getOrNull(2)?.trim().orEmpty().ifBlank { stock.code },
            name = preferredQuoteName(stock),
            market = stock.market,
            securityTypeName = stock.securityTypeName,
            priceDecimalDigits = NativeSecurityPriceScale.resolvePriceDecimalDigits(stock.code, stock.securityTypeName),
            lastPrice = lastPrice,
            previousClose = previousClose,
            changeAmount = changeAmount,
            changePercent = changePercent,
            openPrice = openPrice,
            highPrice = highPrice,
            lowPrice = lowPrice,
            volume = volume,
            timestampMillis = clock(),
        )
    }

    private fun parseEastmoneyQuote(
        stock: NativeStock,
        data: JSONObject,
        timestampMillis: Long,
        codeKeys: List<String>,
        previousCloseKeys: List<String>,
        percentValue: Any?,
    ): NativeQuote {
        val quoteCode = readFirstNonBlankString(data, codeKeys).ifBlank { stock.code }
        val priceDecimalDigits = priceDecimalDigits(data, stock, quoteCode)
        val previousClose = scaledPrice(stock, firstUsableValue(data, previousCloseKeys), priceDecimalDigits).takeIf { it != 0.0 }
            ?: scaledPrice(stock, data.opt("f18"), priceDecimalDigits)

        return NativeQuote(
            code = quoteCode,
            name = preferredQuoteName(stock),
            market = stock.market,
            securityTypeName = stock.securityTypeName,
            priceDecimalDigits = priceDecimalDigits,
            lastPrice = scaledPrice(stock, data.opt("f43"), priceDecimalDigits),
            previousClose = previousClose,
            changeAmount = scaledPrice(stock, data.opt("f169"), priceDecimalDigits),
            changePercent = scaledPercent(percentValue),
            openPrice = scaledPrice(stock, data.opt("f46"), priceDecimalDigits),
            highPrice = scaledPrice(stock, data.opt("f44"), priceDecimalDigits),
            lowPrice = scaledPrice(stock, data.opt("f45"), priceDecimalDigits),
            volume = plainNumber(data.opt("f47")),
            timestampMillis = timestampMillis,
        )
    }

    private fun loadJsonWithRetry(url: URL, referer: String): JSONObject {
        var lastError: Exception? = null
        for (attempt in 0..requestRetryBackoffsMillis.size) {
            try {
                val loader = jsonLoader
                return if (loader != null) loader(url) else JSONObject(loadText(url, "application/json, text/plain, */*", referer, false))
            } catch (error: Exception) {
                if (!shouldRetryRequest(error, attempt)) {
                    throw error
                }
                lastError = error
            }
            if (attempt < requestRetryBackoffsMillis.size) {
                sleepBeforeRetry(requestRetryBackoffsMillis[attempt])
            }
        }
        throw lastError ?: IllegalStateException("行情刷新失败")
    }

    private fun loadTextWithRetry(url: URL, accept: String, referer: String, latin1: Boolean): String {
        var lastError: Exception? = null
        for (attempt in 0..requestRetryBackoffsMillis.size) {
            try {
                val loader = textLoader
                return if (loader != null) loader(url) else loadText(url, accept, referer, latin1)
            } catch (error: Exception) {
                if (!shouldRetryRequest(error, attempt)) {
                    throw error
                }
                lastError = error
            }
            if (attempt < requestRetryBackoffsMillis.size) {
                sleepBeforeRetry(requestRetryBackoffsMillis[attempt])
            }
        }
        throw lastError ?: IllegalStateException("行情刷新失败")
    }

    private fun loadText(url: URL, accept: String, referer: String, latin1: Boolean): String {
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 8000
            readTimeout = 8000
            setRequestProperty("Accept", accept)
            setRequestProperty("User-Agent", "Mozilla/5.0")
            setRequestProperty("Referer", referer)
            setRequestProperty("Connection", "close")
        }
        try {
            val status = connection.responseCode
            if (status !in 200..299) {
                throw IllegalStateException("接口请求失败: $status")
            }
            val bytes = connection.inputStream.use { it.readBytes() }
            return if (latin1) String(bytes, Charsets.ISO_8859_1) else String(bytes, Charsets.UTF_8)
        } finally {
            connection.disconnect()
        }
    }

    private fun sleepBeforeRetry(delayMillis: Long) {
        try {
            sleeper(delayMillis)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            throw IllegalStateException("行情刷新被中断")
        }
    }

    private fun scaledPrice(stock: NativeStock, rawValue: Any?, priceDecimalDigits: Int): Double {
        val plain = plainNumber(rawValue)
        if (isExplicitDecimalValue(rawValue, plain, priceDecimalDigits)) {
            return plain
        }
        return plain / NativeSecurityPriceScale.divisorFor(stock.code, stock.securityTypeName, priceDecimalDigits = priceDecimalDigits)
    }

    private fun scaledPercent(rawValue: Any?): Double = plainNumber(rawValue) / 100.0

    private fun priceDecimalDigits(json: JSONObject, stock: NativeStock, quoteCode: String): Int {
        return NativeSecurityPriceScale.resolvePriceDecimalDigits(
            code = quoteCode,
            securityTypeName = stock.securityTypeName,
            eastmoneyPriceDecimalDigits = json.opt("f59"),
        )
    }

    private fun plainNumber(value: Any?): Double {
        if (value == null || value == JSONObject.NULL) {
            return 0.0
        }
        return when (value) {
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull() ?: 0.0
            else -> 0.0
        }
    }

    private fun preferredQuoteName(stock: NativeStock): String {
        val fallback = stock.name.trim()
        return if (isReadableStockName(fallback)) fallback else stock.code
    }

    private fun isReadableStockName(value: String): Boolean {
        if (value.isBlank()) {
            return false
        }
        if (Regex("^[0-9]{6}$").matches(value)) {
            return false
        }
        val suspiciousFragments = listOf("脙", "脗", "鈧", "锟", "�")
        return suspiciousFragments.none { value.contains(it) }
    }

    private fun isExplicitDecimalValue(rawValue: Any?, plain: Double, priceDecimalDigits: Int): Boolean {
        if (plain == 0.0 || priceDecimalDigits <= 0) {
            return false
        }
        return when (rawValue) {
            is Double -> true
            is Float -> true
            is Number -> rawValue.toDouble() % 1.0 != 0.0
            is String -> rawValue.contains(".")
            else -> false
        }
    }

    private fun hasUsableField(json: JSONObject, keys: List<String>): Boolean = firstUsableValue(json, keys) != null

    private fun hasUsableNumber(json: JSONObject, keys: List<String>): Boolean = tryParseFiniteNumber(firstUsableValue(json, keys)) != null

    private fun firstUsableValue(json: JSONObject, keys: List<String>): Any? {
        for (key in keys) {
            if (!json.has(key) || json.isNull(key)) {
                continue
            }
            val value = json.opt(key)
            if (isDirtyPlaceholder(value)) {
                continue
            }
            return value
        }
        return null
    }

    private fun readFirstNonBlankString(json: JSONObject, keys: List<String>): String {
        for (key in keys) {
            if (!json.has(key) || json.isNull(key)) {
                continue
            }
            val text = json.opt(key)?.toString()?.trim().orEmpty()
            if (text.isNotEmpty()) {
                return text
            }
        }
        return ""
    }

    private fun isDirtyPlaceholder(value: Any?): Boolean {
        if (value == null || value == JSONObject.NULL) {
            return true
        }
        if (value !is String) {
            return false
        }
        val trimmed = value.trim()
        return trimmed.isEmpty() || trimmed == "-"
    }

    private fun tryParseFiniteNumber(value: Any?): Double? {
        if (isDirtyPlaceholder(value)) {
            return null
        }
        if (value is Number) {
            val number = value.toDouble()
            return if (number.isFinite()) number else null
        }
        val parsed = value?.toString()?.trim()?.toDoubleOrNull() ?: return null
        return if (parsed.isFinite()) parsed else null
    }

    private fun normalizeBatchPercent(stock: NativeStock, data: JSONObject): Any? {
        val rawValue = firstUsableValue(data, listOf("f170", "f3")) ?: return null
        val rawPercent = plainNumber(rawValue)
        val quoteCode = readFirstNonBlankString(data, listOf("f57", "f12")).ifBlank { stock.code }
        val priceDecimalDigits = priceDecimalDigits(data, stock, quoteCode)
        val previousClose = scaledPrice(stock, firstUsableValue(data, listOf("f60", "f18")), priceDecimalDigits).takeIf { it != 0.0 }
            ?: scaledPrice(stock, data.opt("f18"), priceDecimalDigits)
        val changeAmount = scaledPrice(stock, data.opt("f169"), priceDecimalDigits)
        if (previousClose == 0.0) {
            return rawValue
        }
        val expectedPercent = changeAmount / previousClose * 100.0
        val directDiff = abs(rawPercent / 100.0 - expectedPercent)
        val scaledDiff = abs(rawPercent - expectedPercent)
        return if (scaledDiff < directDiff) rawPercent * 100.0 else rawValue
    }

    private fun isSaneBatchQuote(quote: NativeQuote): Boolean {
        if (quote.lastPrice <= 0.0 || quote.previousClose <= 0.0 || quote.openPrice < 0.0 || quote.highPrice < 0.0 || quote.lowPrice < 0.0 || quote.volume < 0.0) {
            return false
        }
        val tickSize = 1.0 / quote.priceScaleDivisor()
        val priceTolerance = tickSize * 2.0
        val expectedChangeAmount = quote.lastPrice - quote.previousClose
        if (abs(quote.changeAmount - expectedChangeAmount) > priceTolerance) {
            return false
        }
        if (quote.highPrice + priceTolerance < quote.lowPrice) {
            return false
        }
        if (quote.lastPrice < quote.lowPrice - priceTolerance || quote.lastPrice > quote.highPrice + priceTolerance || quote.openPrice < quote.lowPrice - priceTolerance || quote.openPrice > quote.highPrice + priceTolerance) {
            return false
        }
        val expectedPercent = expectedChangeAmount / quote.previousClose * 100.0
        val percentTolerance = maxOf(0.35, abs(expectedPercent) * 0.1)
        return abs(quote.changePercent - expectedPercent) <= percentTolerance
    }

    private fun isUsableSingleQuote(quote: NativeQuote): Boolean {
        if (quote.lastPrice <= 0.0 || quote.previousClose <= 0.0 || quote.openPrice <= 0.0 || quote.highPrice <= 0.0 || quote.lowPrice <= 0.0 || quote.volume < 0.0) {
            return false
        }
        val tickSize = 1.0 / quote.priceScaleDivisor()
        val priceTolerance = tickSize * 2.0
        val expectedChangeAmount = quote.lastPrice - quote.previousClose
        if (abs(quote.changeAmount - expectedChangeAmount) > priceTolerance) {
            return false
        }
        if (quote.highPrice + priceTolerance < quote.lowPrice) {
            return false
        }
        if (quote.lastPrice < quote.lowPrice - priceTolerance || quote.lastPrice > quote.highPrice + priceTolerance || quote.openPrice < quote.lowPrice - priceTolerance || quote.openPrice > quote.highPrice + priceTolerance) {
            return false
        }
        val expectedPercent = expectedChangeAmount / quote.previousClose * 100.0
        val percentTolerance = maxOf(0.35, abs(expectedPercent) * 0.1)
        return abs(quote.changePercent - expectedPercent) <= percentTolerance
    }

    private fun parseTencentQuoteFields(payload: String): List<String> {
        val start = payload.indexOf('"')
        val end = payload.lastIndexOf('"')
        if (start < 0 || end <= start) {
            throw IllegalStateException("Tencent quote payload format is invalid")
        }
        return payload.substring(start + 1, end).split('~')
    }

    private fun parseTencentNumber(fields: List<String>, index: Int): Double? {
        if (index >= fields.size) {
            return null
        }
        val text = fields[index].trim()
        if (text.isEmpty()) {
            return null
        }
        return text.toDoubleOrNull()
    }

    private fun shouldRetryRequest(error: Exception, attempt: Int): Boolean {
        if (attempt >= requestRetryBackoffsMillis.size) {
            return false
        }
        if (error is SocketTimeoutException) {
            return true
        }
        if (error is IOException) {
            val message = error.message.orEmpty().lowercase(Locale.ROOT)
            return message.contains("unexpected end of stream") ||
                message.contains("connection reset") ||
                message.contains("connection closed") ||
                message.contains("connection terminated") ||
                message.contains("timed out") ||
                message.contains("timeout") ||
                message.contains("eof")
        }
        val message = error.message.orEmpty().lowercase(Locale.ROOT)
        val statusMatch = Regex("接口请求失败: (\\d{3})").find(message)
        val statusCode = statusMatch?.groupValues?.getOrNull(1)?.toIntOrNull()
        return statusCode == 408 || statusCode == 429 || statusCode == 500 || statusCode == 502 || statusCode == 503 || statusCode == 504
    }
}

private fun NativeQuote.priceScaleDivisor(): Double {
    return NativeSecurityPriceScale.divisorFor(
        code = code,
        securityTypeName = securityTypeName,
        priceDecimalDigits = priceDecimalDigits,
    )
}

private data class NativeBatchQuoteResult(
    val quotesByCode: Map<String, NativeQuote>,
    val fallbackStocks: List<NativeStock>,
)

private data class NativeTencentQuoteLayout(
    val changeAmountIndex: Int,
    val changePercentIndex: Int,
    val highPriceIndex: Int,
    val lowPriceIndex: Int,
    val volumeIndex: Int,
)
