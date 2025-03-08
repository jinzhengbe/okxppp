class PriceData {
  final DateTime timestamp;
  final String symbol;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final double quoteVolume;
  final String exchange;

  PriceData({
    required this.timestamp,
    required this.symbol,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.quoteVolume,
    required this.exchange,
  });

  // 从JSON创建
  factory PriceData.fromJson(Map<String, dynamic> json) {
    return PriceData(
      timestamp: DateTime.parse(json['timestamp']),
      symbol: json['symbol'],
      open: json['open'].toDouble(),
      high: json['high'].toDouble(),
      low: json['low'].toDouble(),
      close: json['close'].toDouble(),
      volume: json['volume'].toDouble(),
      quoteVolume: json['quoteVolume'].toDouble(),
      exchange: json['exchange'],
    );
  }

  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'symbol': symbol,
      'open': open,
      'high': high,
      'low': low,
      'close': close,
      'volume': volume,
      'quoteVolume': quoteVolume,
      'exchange': exchange,
    };
  }

  // 转换为InfluxDB点
  Map<String, dynamic> toInfluxPoint() {
    return {
      'measurement': 'price_data',
      'tags': {
        'symbol': symbol,
        'exchange': exchange,
      },
      'fields': {
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        'volume': volume,
        'quoteVolume': quoteVolume,
      },
      'time': timestamp.toUtc().millisecondsSinceEpoch * 1000000, // 纳秒时间戳
    };
  }

  // 从Ticker创建PriceData
  factory PriceData.fromTicker(dynamic ticker, String exchange) {
    return PriceData(
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(int.parse(ticker.timestamp)),
      symbol: ticker.symbol,
      open: double.parse(ticker.open24h),
      high: double.parse(ticker.high24h),
      low: double.parse(ticker.low24h),
      close: double.parse(ticker.last),
      volume: double.parse(ticker.vol24h),
      quoteVolume: double.parse(ticker.volCcy24h),
      exchange: exchange,
    );
  }
}
