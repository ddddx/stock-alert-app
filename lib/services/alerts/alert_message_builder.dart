import '../../core/utils/formatters.dart';
import '../../data/models/alert_rule.dart';
import '../../data/models/stock_quote_snapshot.dart';

class AlertMessageBuilder {
  String buildPreviewText(StockQuoteSnapshot? quote) {
    if (quote == null) {
      return '\u8bed\u97f3\u9884\u89c8\uff0c\u5f53\u524d\u6ca1\u6709\u53ef\u7528\u884c\u60c5\u3002'
          '\u8bf7\u5148\u5237\u65b0\u81ea\u9009\uff0c\u518d\u8bd5\u64ad\u5177\u4f53\u80a1\u7968\u63d0\u9192\u6587\u6848\u3002';
    }
    return '${quote.name}${quote.code}\uFF0C'
        '\u5F53\u524D\u4EF7\u683C${Formatters.priceForSecurity(quote.lastPrice, code: quote.code, securityTypeName: quote.securityTypeName, priceDecimalDigits: quote.resolvedPriceDecimalDigits)}\uFF0C'
        '\u6DA8\u8DCC\u989D${Formatters.signedPriceForSecurity(quote.changeAmount, code: quote.code, securityTypeName: quote.securityTypeName, priceDecimalDigits: quote.resolvedPriceDecimalDigits)}\uFF0C'
        '\u6DA8\u8DCC\u5E45${Formatters.percent(quote.changePercent)}\u3002';
  }

  String buildShortWindowMessage({
    required AlertRule rule,
    required StockQuoteSnapshot current,
    required double changeAmount,
    required double changePercent,
  }) {
    final direction = changeAmount >= 0 ? '\u4e0a\u6da8' : '\u4e0b\u8dcc';
    return '${current.name}(${current.code}) '
        '${rule.lookbackMinutes} \u5206\u949f\u5185$direction${changePercent.abs().toStringAsFixed(2)}%\uFF0C'
        '\u53D8\u52A8 ${Formatters.signedPriceForSecurity(changeAmount, code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}\uFF0C'
        '\u73B0\u4EF7 ${Formatters.priceForSecurity(current.lastPrice, code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}\u3002';
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
          '\u6DA8\u8DCC\u5E45\u8DE8\u8FC7${(currentIndex * (rule.stepValue ?? 0)).toStringAsFixed(2)}% \u53F0\u9636\uFF0C'
          '\u672C\u6B21\u7D2F\u8BA1\u6CE2\u52A8 ${Formatters.signedPriceForSecurity(crossedAmount, code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}\uFF0C'
          '\u7D2F\u8BA1\u6DA8\u8DCC\u5E45${Formatters.percent(crossedPercent)}\uFF0C'
          '\u5F53\u524D\u6DA8\u8DCC\u5E45${Formatters.percent(current.changePercent)}\uFF0C'
          '\u73B0\u4EF7 ${Formatters.priceForSecurity(current.lastPrice, code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}\u3002';
    }

    return '${current.name}(${current.code}) '
        '\u4EF7\u683C\u4ECE${Formatters.priceForSecurity(referenceValue + previousIndex * (rule.stepValue ?? 0), code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)} '
        '\u8DE8\u5230${Formatters.priceForSecurity(referenceValue + currentIndex * (rule.stepValue ?? 0), code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)} \u53F0\u9636\uFF0C'
        '\u672C\u6B21\u7D2F\u8BA1\u6CE2\u52A8 ${Formatters.signedPriceForSecurity(crossedAmount, code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}\uFF0C'
        '\u7D2F\u8BA1\u6DA8\u8DCC\u5E45${Formatters.percent(crossedPercent)}\uFF0C'
        '\u5F53\u524D\u4EF7\u683C ${Formatters.priceForSecurity(current.lastPrice, code: current.code, securityTypeName: current.securityTypeName, priceDecimalDigits: current.resolvedPriceDecimalDigits)}\u3002';
  }
}
