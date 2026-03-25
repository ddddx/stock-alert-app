import '../../core/utils/formatters.dart';
import '../../data/models/alert_rule.dart';
import '../../data/models/stock_quote_snapshot.dart';

class AlertMessageBuilder {
  String buildPreviewText(StockQuoteSnapshot? quote) {
    if (quote == null) {
      return '语音预览，当前没有可用行情。请先刷新自选，再试播具体股票提醒文案。';
    }
    return '${quote.name}${quote.code}，当前价格${Formatters.price(quote.lastPrice)}，'
        '涨跌额${Formatters.signedPrice(quote.changeAmount)}，'
        '涨跌幅${Formatters.percent(quote.changePercent)}。';
  }

  String buildShortWindowMessage({
    required AlertRule rule,
    required StockQuoteSnapshot current,
    required double changeAmount,
    required double changePercent,
  }) {
    final direction = changeAmount >= 0 ? '上涨' : '下跌';
    return '${current.name}(${current.code}) '
        '${rule.lookbackMinutes} 分钟内$direction${changePercent.abs().toStringAsFixed(2)}%，'
        '变动 ${Formatters.signedPrice(changeAmount)}，'
        '现价 ${Formatters.price(current.lastPrice)}。';
  }

  String buildStepAlertMessage({
    required AlertRule rule,
    required StockQuoteSnapshot current,
    required int previousIndex,
    required int currentIndex,
    required double referenceValue,
    required double crossedAmount,
    required double crossedPercent,
  }) {
    if (rule.stepMetric == StepMetric.percent) {
      return '${current.name}(${current.code}) '
          '涨跌幅跨过 ${(currentIndex * (rule.stepValue ?? 0)).toStringAsFixed(2)}% 台阶，'
          '本次累计波动 ${Formatters.signedPrice(crossedAmount)}，'
          '累计涨跌幅 ${Formatters.percent(crossedPercent)}，'
          '当前涨跌幅 ${Formatters.percent(current.changePercent)}，'
          '现价 ${Formatters.price(current.lastPrice)}。';
    }

    return '${current.name}(${current.code}) '
        '价格从 ${Formatters.price(referenceValue + previousIndex * (rule.stepValue ?? 0))} '
        '跨到 ${Formatters.price(referenceValue + currentIndex * (rule.stepValue ?? 0))} 台阶，'
        '本次累计波动 ${Formatters.signedPrice(crossedAmount)}，'
        '累计涨跌幅 ${Formatters.percent(crossedPercent)}，'
        '当前价格 ${Formatters.price(current.lastPrice)}。';
  }
}
