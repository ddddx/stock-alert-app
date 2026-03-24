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
  }) {
    if (rule.stepMetric == StepMetric.percent) {
      return '${current.name}${current.code}，涨跌幅从'
          '${(previousIndex * (rule.stepValue ?? 0)).toStringAsFixed(2)}% '
          '跨到 ${(currentIndex * (rule.stepValue ?? 0)).toStringAsFixed(2)}% 台阶，'
          '当前涨跌幅 ${Formatters.percent(current.changePercent)}，'
          '现价 ${Formatters.price(current.lastPrice)}。';
    }

    return '${current.name}${current.code}，价格跨过 '
        '${Formatters.price(referenceValue + previousIndex * (rule.stepValue ?? 0))} '
        '到 ${Formatters.price(referenceValue + currentIndex * (rule.stepValue ?? 0))} 的台阶，'
        '当前价格 ${Formatters.price(current.lastPrice)}。';
  }
}
