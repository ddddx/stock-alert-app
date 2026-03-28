import '../../core/utils/formatters.dart';
import '../../data/models/alert_rule.dart';
import '../../data/models/stock_quote_snapshot.dart';

class AlertMessageBuilder {
  String buildPreviewText(StockQuoteSnapshot? quote) {
    if (quote == null) {
      return '语音预览暂时拿不到可用行情。请先刷新自选，再试试真实播报文案。';
    }
    return '${_stockSubject(quote)}，当前${_directionLabel(quote.changeAmount)}'
        '${Formatters.percent(quote.changePercent)}，'
        '变动${Formatters.signedPriceForSecurity(quote.changeAmount, code: quote.code, securityTypeName: quote.securityTypeName, priceDecimalDigits: quote.resolvedPriceDecimalDigits)}，'
        '最新价${Formatters.priceForSecurity(quote.lastPrice, code: quote.code, securityTypeName: quote.securityTypeName, priceDecimalDigits: quote.resolvedPriceDecimalDigits)}。';
  }

  String buildShortWindowMessage({
    required AlertRule rule,
    required StockQuoteSnapshot current,
    required double changeAmount,
    required double changePercent,
  }) {
    final direction = _directionLabel(changeAmount);
    final action = changeAmount >= 0 ? '拉升' : '回落';
    return '${_stockSubject(current)}触发短时波动提醒，'
        '${rule.lookbackMinutes}分钟内$direction${changePercent.abs().toStringAsFixed(2)}%，'
        '$action${Formatters.signedPriceForSecurity(changeAmount, code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}，'
        '最新价${Formatters.priceForSecurity(current.lastPrice, code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}。';
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
    final direction = _directionLabel(crossedAmount);
    if (rule.stepMetric == StepMetric.percent) {
      return '${_stockSubject(current)}触发阶梯提醒，'
          '涨跌幅已越过${(currentIndex * (rule.stepValue ?? 0)).toStringAsFixed(2)}%台阶，'
          '累计$direction${Formatters.percent(crossedPercent).replaceFirst('+', '').replaceFirst('-', '')}，'
          '对应变动${Formatters.signedPriceForSecurity(crossedAmount, code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}，'
          '当前涨跌幅${Formatters.percent(current.changePercent)}，'
          '最新价${Formatters.priceForSecurity(current.lastPrice, code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}。';
    }

    return '${_stockSubject(current)}触发阶梯提醒，'
        '价格从${Formatters.priceForSecurity(referenceValue + previousIndex * (rule.stepValue ?? 0), code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}跨到'
        '${Formatters.priceForSecurity(referenceValue + currentIndex * (rule.stepValue ?? 0), code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}这一档，'
        '累计$direction${Formatters.percent(crossedPercent).replaceFirst('+', '').replaceFirst('-', '')}，'
        '对应变动${Formatters.signedPriceForSecurity(crossedAmount, code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}，'
        '最新价${Formatters.priceForSecurity(current.lastPrice, code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}。';
  }

  String _stockSubject(StockQuoteSnapshot quote) {
    if (quote.code.trim().isEmpty) {
      return quote.name;
    }
    return '${quote.name}（${quote.code}）';
  }

  String _directionLabel(double value) {
    if (value > 0) {
      return '上涨';
    }
    if (value < 0) {
      return '下跌';
    }
    return '持平';
  }
}
