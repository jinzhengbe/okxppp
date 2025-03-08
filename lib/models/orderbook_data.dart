class OrderBookEntry {
  final double price;
  final double amount;

  OrderBookEntry({
    required this.price,
    required this.amount,
  });

  factory OrderBookEntry.fromJson(Map<String, dynamic> json) {
    return OrderBookEntry(
      price: json['price'].toDouble(),
      amount: json['amount'].toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'price': price,
      'amount': amount,
    };
  }
}

class OrderBookData {
  final DateTime timestamp;
  final String symbol;
  final String exchange;
  final List<OrderBookEntry> bids; // 买单
  final List<OrderBookEntry> asks; // 卖单

  OrderBookData({
    required this.timestamp,
    required this.symbol,
    required this.exchange,
    required this.bids,
    required this.asks,
  });

  // 从JSON创建
  factory OrderBookData.fromJson(Map<String, dynamic> json) {
    return OrderBookData(
      timestamp: DateTime.parse(json['timestamp']),
      symbol: json['symbol'],
      exchange: json['exchange'],
      bids: (json['bids'] as List)
          .map((bid) => OrderBookEntry.fromJson(bid))
          .toList(),
      asks: (json['asks'] as List)
          .map((ask) => OrderBookEntry.fromJson(ask))
          .toList(),
    );
  }

  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'symbol': symbol,
      'exchange': exchange,
      'bids': bids.map((bid) => bid.toJson()).toList(),
      'asks': asks.map((ask) => ask.toJson()).toList(),
    };
  }

  // 转换为InfluxDB点
  Map<String, dynamic> toInfluxPoint() {
    // 为了简化，我们只存储前5个买单和卖单
    final topBids = bids.take(5).toList();
    final topAsks = asks.take(5).toList();

    Map<String, dynamic> fields = {};

    // 添加买单
    for (int i = 0; i < topBids.length; i++) {
      fields['bid_price_$i'] = topBids[i].price;
      fields['bid_amount_$i'] = topBids[i].amount;
    }

    // 添加卖单
    for (int i = 0; i < topAsks.length; i++) {
      fields['ask_price_$i'] = topAsks[i].price;
      fields['ask_amount_$i'] = topAsks[i].amount;
    }

    // 计算买卖价差
    if (topAsks.isNotEmpty && topBids.isNotEmpty) {
      fields['spread'] = topAsks[0].price - topBids[0].price;
      fields['spread_percentage'] =
          (topAsks[0].price - topBids[0].price) / topBids[0].price * 100;
    }

    return {
      'measurement': 'orderbook_data',
      'tags': {
        'symbol': symbol,
        'exchange': exchange,
      },
      'fields': fields,
      'time': timestamp.toUtc().millisecondsSinceEpoch * 1000000, // 纳秒时间戳
    };
  }

  // 计算买单总量
  double get totalBidVolume => bids.fold(0, (sum, bid) => sum + bid.amount);

  // 计算卖单总量
  double get totalAskVolume => asks.fold(0, (sum, ask) => sum + ask.amount);

  // 计算买卖比率
  double get bidAskRatio =>
      totalBidVolume / (totalAskVolume > 0 ? totalAskVolume : 1);

  // 获取最佳买价
  double? get bestBidPrice => bids.isNotEmpty ? bids.first.price : null;

  // 获取最佳卖价
  double? get bestAskPrice => asks.isNotEmpty ? asks.first.price : null;

  // 计算买卖价差
  double? get spread => (bestAskPrice != null && bestBidPrice != null)
      ? bestAskPrice! - bestBidPrice!
      : null;
}
