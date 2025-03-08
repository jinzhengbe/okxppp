class TradeData {
  final String tradeId;
  final DateTime timestamp;
  final String symbol;
  final double price;
  final double amount;
  final String direction; // 'buy' 或 'sell'
  final String exchange;
  final String type; // 'market', 'limit' 等
  final double fee;

  TradeData({
    required this.tradeId,
    required this.timestamp,
    required this.symbol,
    required this.price,
    required this.amount,
    required this.direction,
    required this.exchange,
    required this.type,
    required this.fee,
  });

  // 从JSON创建
  factory TradeData.fromJson(Map<String, dynamic> json) {
    return TradeData(
      tradeId: json['trade_id'],
      timestamp: DateTime.parse(json['timestamp']),
      symbol: json['symbol'],
      price: json['price'].toDouble(),
      amount: json['amount'].toDouble(),
      direction: json['direction'],
      exchange: json['exchange'],
      type: json['type'],
      fee: json['fee'].toDouble(),
    );
  }

  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'trade_id': tradeId,
      'timestamp': timestamp.toIso8601String(),
      'symbol': symbol,
      'price': price,
      'amount': amount,
      'direction': direction,
      'exchange': exchange,
      'type': type,
      'fee': fee,
    };
  }

  // 转换为PostgreSQL插入格式
  Map<String, dynamic> toPostgresInsert() {
    return {
      'trade_id': tradeId,
      'timestamp': timestamp.toIso8601String(),
      'symbol': symbol,
      'price': price,
      'amount': amount,
      'direction': direction,
      'exchange': exchange,
      'type': type,
      'fee': fee,
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  // 计算交易总价值
  double get totalValue => price * amount;

  // 计算交易手续费价值
  double get feeValue => totalValue * fee / 100;
}
