package com.stockpulse.radar

interface NativeQuoteDataSource {
    fun fetchQuotes(stocks: List<NativeStock>): NativeQuoteFetchResult
}
