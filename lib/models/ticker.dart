class Ticker {
  final String symbol;
  final String last;
  final String open24h;
  final String high24h;
  final String low24h;
  final String volCcy24h;
  final String vol24h;
  final String change24h;
  final String changeRate24h;
  final String askPx;
  final String askSz;
  final String bidPx;
  final String bidSz;
  final String timestamp;

  Ticker({
    required this.symbol,
    required this.last,
    required this.open24h,
    required this.high24h,
    required this.low24h,
    required this.volCcy24h,
    required this.vol24h,
    required this.change24h,
    required this.changeRate24h,
    required this.askPx,
    required this.askSz,
    required this.bidPx,
    required this.bidSz,
    required this.timestamp,
  });

  factory Ticker.fromJson(Map<String, dynamic> json) {
    try {
      print('解析Ticker数据: $json');
      return Ticker(
        symbol: json['instId'] ?? '',
        last: json['last'] ?? '0',
        open24h: json['open24h'] ?? '0',
        high24h: json['high24h'] ?? '0',
        low24h: json['low24h'] ?? '0',
        volCcy24h: json['volCcy24h'] ?? '0',
        vol24h: json['vol24h'] ?? '0',
        change24h: json['change24h'] ?? '0',
        changeRate24h: json['changeRate24h'] ?? '0',
        askPx: json['askPx'] ?? '0',
        askSz: json['askSz'] ?? '0',
        bidPx: json['bidPx'] ?? '0',
        bidSz: json['bidSz'] ?? '0',
        timestamp:
            json['ts'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      );
    } catch (e) {
      print('Ticker解析错误: $e, 原始数据: $json');
      // 返回一个默认的Ticker对象，避免应用崩溃
      return Ticker(
        symbol: '',
        last: '0',
        open24h: '0',
        high24h: '0',
        low24h: '0',
        volCcy24h: '0',
        vol24h: '0',
        change24h: '0',
        changeRate24h: '0',
        askPx: '0',
        askSz: '0',
        bidPx: '0',
        bidSz: '0',
        timestamp: DateTime.now().millisecondsSinceEpoch.toString(),
      );
    }
  }

  // 获取价格变化百分比
  double get changePercentage => double.tryParse(changeRate24h) != null
      ? double.parse(changeRate24h) * 100
      : 0.0;

  // 获取当前价格
  double get currentPrice =>
      double.tryParse(last) != null ? double.parse(last) : 0.0;

  // 获取24小时最高价
  double get highPrice =>
      double.tryParse(high24h) != null ? double.parse(high24h) : 0.0;

  // 获取24小时最低价
  double get lowPrice =>
      double.tryParse(low24h) != null ? double.parse(low24h) : 0.0;

  // 获取24小时交易量
  double get volume =>
      double.tryParse(volCcy24h) != null ? double.parse(volCcy24h) : 0.0;

  // 价格是否上涨
  bool get isPriceUp =>
      double.tryParse(change24h) != null ? double.parse(change24h) > 0 : false;

  Map<String, dynamic> toJson() {
    return {
      'instId': symbol,
      'last': last,
      'open24h': open24h,
      'high24h': high24h,
      'low24h': low24h,
      'volCcy24h': volCcy24h,
      'vol24h': vol24h,
      'change24h': change24h,
      'changeRate24h': changeRate24h,
      'askPx': askPx,
      'askSz': askSz,
      'bidPx': bidPx,
      'bidSz': bidSz,
      'ts': timestamp,
    };
  }
}
