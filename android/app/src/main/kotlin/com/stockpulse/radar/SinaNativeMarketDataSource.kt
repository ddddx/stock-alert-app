package com.stockpulse.radar

import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.Charset
import java.util.Locale
import kotlin.math.abs

class SinaNativeMarketDataSource(
    private val textLoader: ((URL) -> String)? = null,
    private val sleeper: (Long) -> Unit = { Thread.sleep(it) },
    private val clock: () -> Long = { System.currentTimeMillis() },
) : NativeQuoteDataSource {
    companion object {
        private const val sinaReferer = "https://finance.sina.com.cn"
        private val gb18030 = Charset.forName("GB18030")
        private val requestRetryBackoffsMillis = listOf(250L, 500L)
    }

    fun searchStocks(keyword: String): List<Map<String, Any>> {
        val query = keyword.trim()
        if (query.isEmpty()) {
            return emptyList()
        }

        val encodedKeyword = URLEncoder.encode(query, Charsets.UTF_8.name())
        val url = URL("https://suggest3.sinajs.cn/suggest/type=&key=$encodedKeyword")
        val payload = extractQuotedPayload(loadTextWithRetry(url))
        if (payload.isBlank()) {
            return emptyList()
        }

        return payload.split(';')
            .mapNotNull(::parseSearchEntry)
            .distinctBy { stock -> "${stock["market"]}-${stock["code"]}" }
    }

    override fun fetchQuotes(stocks: List<NativeStock>): NativeQuoteFetchResult {
        if (stocks.isEmpty()) {
            return NativeQuoteFetchResult(
                quotes = emptyList(),
                failedCount = 0,
            )
        }

        val stocksByPrefixedCode = stocks.associateBy(::prefixedCode)
        val quotesByCode = linkedMapOf<String, NativeQuote>()
        var failedCount = 0
        var lastError: Exception? = null

        try {
            val joinedCodes = stocksByPrefixedCode.keys.joinToString(",")
            val url = URL("https://hq.sinajs.cn/list=$joinedCodes")
            val payload = loadTextWithRetry(url)
            quotesByCode.putAll(parseBatchQuotes(payload, stocksByPrefixedCode))
        } catch (error: Exception) {
            lastError = error
        }

        val missingStocks = stocks.filter { stock -> !quotesByCode.containsKey(stock.code) }
        missingStocks.forEach { stock ->
            try {
                quotesByCode[stock.code] = fetchQuote(stock)
            } catch (error: Exception) {
                failedCount += 1
                lastError = error
            }
        }

        if (quotesByCode.isEmpty() && lastError != null) {
            throw lastError
        }

        return NativeQuoteFetchResult(
            quotes = stocks.mapNotNull { stock -> quotesByCode[stock.code] },
            failedCount = failedCount,
        )
    }

    private fun fetchQuote(stock: NativeStock): NativeQuote {
        val url = URL("https://hq.sinajs.cn/list=${prefixedCode(stock)}")
        val payload = loadTextWithRetry(url)
        return parseBatchQuotes(payload, mapOf(prefixedCode(stock) to stock))[stock.code]
            ?: throw IllegalStateException("Sina quote payload is empty")
    }

    private fun parseBatchQuotes(
        payload: String,
        stocksByPrefixedCode: Map<String, NativeStock>,
    ): Map<String, NativeQuote> {
        val quotesByCode = linkedMapOf<String, NativeQuote>()
        val regex = Regex("var\\s+hq_str_(\\w+)=\"([^\"]*)\";")
        regex.findAll(payload).forEach { match ->
            val prefixedCode = match.groupValues.getOrNull(1).orEmpty()
            val stock = stocksByPrefixedCode[prefixedCode] ?: return@forEach
            val fields = match.groupValues.getOrNull(2).orEmpty().split(',')
            val quote = parseQuoteFields(stock, fields)
            if (quote != null) {
                quotesByCode[quote.code] = quote
            }
        }
        return quotesByCode
    }

    private fun parseQuoteFields(stock: NativeStock, fields: List<String>): NativeQuote? {
        if (fields.size < 10) {
            return null
        }

        val previousClose = fields.getOrNull(2)?.trim()?.toDoubleOrNull() ?: 0.0
        var lastPrice = fields.getOrNull(3)?.trim()?.toDoubleOrNull() ?: 0.0
        var openPrice = fields.getOrNull(1)?.trim()?.toDoubleOrNull() ?: 0.0
        var highPrice = fields.getOrNull(4)?.trim()?.toDoubleOrNull() ?: 0.0
        var lowPrice = fields.getOrNull(5)?.trim()?.toDoubleOrNull() ?: 0.0
        if (previousClose <= 0.0) {
            return null
        }

        if (lastPrice <= 0.0) {
            lastPrice = previousClose
        }
        if (openPrice <= 0.0) {
            openPrice = previousClose
        }
        if (highPrice <= 0.0) {
            highPrice = lastPrice
        }
        if (lowPrice <= 0.0) {
            lowPrice = lastPrice
        }

        val changeAmount = lastPrice - previousClose
        val changePercent = if (previousClose == 0.0) 0.0 else changeAmount / previousClose * 100.0
        val rawName = fields.firstOrNull().orEmpty().trim()
        val resolvedName = if (isReadableStockName(rawName)) rawName else preferredQuoteName(stock)

        return NativeQuote(
            code = stock.code,
            name = resolvedName,
            market = stock.market,
            securityTypeName = stock.securityTypeName,
            priceDecimalDigits = NativeSecurityPriceScale.resolvePriceDecimalDigits(
                code = stock.code,
                securityTypeName = stock.securityTypeName,
            ),
            lastPrice = lastPrice,
            previousClose = previousClose,
            changeAmount = changeAmount,
            changePercent = changePercent,
            openPrice = openPrice,
            highPrice = highPrice,
            lowPrice = lowPrice,
            volume = fields.getOrNull(8)?.trim()?.toDoubleOrNull() ?: 0.0,
            timestampMillis = parseTimestampMillis(
                fields.getOrNull(30).orEmpty(),
                fields.getOrNull(31).orEmpty(),
            ),
        )
    }

    private fun parseSearchEntry(entry: String): Map<String, Any>? {
        val fields = entry.split(',')
        if (fields.size < 5) {
            return null
        }

        val code = fields.getOrNull(2).orEmpty().trim()
        if (!Regex("^\\d{6}$").matches(code)) {
            return null
        }

        val prefixedCode = sequenceOf(
            fields.getOrNull(3).orEmpty().trim(),
            fields.firstOrNull().orEmpty().trim(),
        ).firstOrNull { value ->
            Regex("^(sh|sz)\\d{6}$", RegexOption.IGNORE_CASE).matches(value)
        } ?: return null

        val market = if (prefixedCode.startsWith("sh", ignoreCase = true)) "SH" else "SZ"
        val rawName = sequenceOf(
            fields.getOrNull(4).orEmpty().trim(),
            fields.getOrNull(6).orEmpty().trim(),
        ).firstOrNull { value -> value.isNotEmpty() } ?: code
        val securityTypeName = inferSecurityTypeName(
            code = code,
            name = rawName,
            rawTypeCode = fields.getOrNull(1).orEmpty().trim(),
        )

        return mapOf(
            "code" to code,
            "name" to if (isReadableStockName(rawName)) rawName else code,
            "market" to market,
            "securityTypeName" to securityTypeName,
            "pinyin" to "",
        )
    }

    private fun prefixedCode(stock: NativeStock): String {
        return stock.market.lowercase(Locale.ROOT) + stock.code
    }

    private fun parseTimestampMillis(dateText: String, timeText: String): Long {
        val dateParts = dateText.trim().split('-')
        val timeParts = timeText.trim().split(':')
        if (dateParts.size != 3 || timeParts.size != 3) {
            return clock()
        }

        val year = dateParts[0].toIntOrNull()
        val month = dateParts[1].toIntOrNull()
        val day = dateParts[2].toIntOrNull()
        val hour = timeParts[0].toIntOrNull()
        val minute = timeParts[1].toIntOrNull()
        val second = timeParts[2].toIntOrNull()
        if (year == null || month == null || day == null || hour == null || minute == null || second == null) {
            return clock()
        }

        val calendar = java.util.Calendar.getInstance()
        calendar.set(year, month - 1, day, hour, minute, second)
        calendar.set(java.util.Calendar.MILLISECOND, 0)
        return calendar.timeInMillis
    }

    private fun loadTextWithRetry(url: URL): String {
        var lastError: Exception? = null
        for (attempt in 0..requestRetryBackoffsMillis.size) {
            try {
                val loader = textLoader
                return if (loader != null) loader(url) else loadText(url)
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

        throw lastError ?: IllegalStateException("Sina request failed")
    }

    private fun loadText(url: URL): String {
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 8000
            readTimeout = 8000
            setRequestProperty("Accept", "application/javascript, text/plain, */*")
            setRequestProperty("User-Agent", "Mozilla/5.0")
            setRequestProperty("Referer", sinaReferer)
            setRequestProperty("Connection", "close")
        }

        try {
            val status = connection.responseCode
            if (status !in 200..299) {
                throw IllegalStateException("接口请求失败: $status")
            }
            val bytes = connection.inputStream.use { it.readBytes() }
            return String(bytes, gb18030)
        } finally {
            connection.disconnect()
        }
    }

    private fun sleepBeforeRetry(delayMillis: Long) {
        try {
            sleeper(delayMillis)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            throw IllegalStateException("Sina request interrupted")
        }
    }

    private fun preferredQuoteName(stock: NativeStock): String {
        val fallback = stock.name.trim()
        return if (isReadableStockName(fallback)) fallback else stock.code
    }

    private fun isReadableStockName(value: String): Boolean {
        if (value.isBlank() || Regex("^[0-9]{6}$").matches(value)) {
            return false
        }
        val suspiciousFragments = listOf("脙", "脗", "鈧", "锟", "�")
        return suspiciousFragments.none { value.contains(it) }
    }

    private fun extractQuotedPayload(payload: String): String {
        val start = payload.indexOf('"')
        val end = payload.lastIndexOf('"')
        if (start < 0 || end <= start) {
            return ""
        }
        return payload.substring(start + 1, end)
    }

    private fun inferSecurityTypeName(code: String, name: String, rawTypeCode: String): String {
        val normalizedName = name.uppercase(Locale.ROOT)
        if (normalizedName.contains("ETF")) {
            return "ETF"
        }
        if (normalizedName.contains("LOF")) {
            return "LOF"
        }
        if (normalizedName.contains("REIT")) {
            return "REIT"
        }
        if (normalizedName.contains("转债") ||
            normalizedName.contains("债") ||
            Regex("^(11|12)\\d{4}$").matches(code)
        ) {
            return "债券"
        }
        if (rawTypeCode == "201" ||
            rawTypeCode == "203" ||
            rawTypeCode == "23" ||
            Regex("^(5\\d{5}|1[56]\\d{4})$").matches(code)
        ) {
            return "基金"
        }
        return "股票"
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
