class Order {
  final String orderId;
  final String symbol;
  final String side;
  final String orderType;
  final String price;
  final String avgPrice;
  final String size;
  final String filledSize;
  final String state;
  final String createTime;
  final String updateTime;

  Order({
    required this.orderId,
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.price,
    required this.avgPrice,
    required this.size,
    required this.filledSize,
    required this.state,
    required this.createTime,
    required this.updateTime,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      orderId: json['ordId'] ?? '',
      symbol: json['instId'] ?? '',
      side: json['side'] ?? '',
      orderType: json['ordType'] ?? '',
      price: json['px'] ?? '0',
      avgPrice: json['avgPx'] ?? '0',
      size: json['sz'] ?? '0',
      filledSize: json['accFillSz'] ?? '0',
      state: json['state'] ?? '',
      createTime: json['cTime'] ?? '',
      updateTime: json['uTime'] ?? '',
    );
  }

  // 获取订单状态描述
  String get stateDescription {
    switch (state) {
      case 'live':
        return '活跃';
      case 'canceled':
        return '已取消';
      case 'partially_filled':
        return '部分成交';
      case 'filled':
        return '已成交';
      default:
        return '未知';
    }
  }

  // 获取订单方向描述
  String get sideDescription {
    switch (side) {
      case 'buy':
        return '买入';
      case 'sell':
        return '卖出';
      default:
        return '未知';
    }
  }

  // 获取订单类型描述
  String get orderTypeDescription {
    switch (orderType) {
      case 'market':
        return '市价单';
      case 'limit':
        return '限价单';
      default:
        return '未知';
    }
  }

  // 检查订单是否已完成
  bool get isCompleted {
    return state == 'filled' || state == 'canceled';
  }

  // 检查订单是否成功
  bool get isSuccessful {
    return state == 'filled';
  }

  // 获取成交金额
  double get filledAmount {
    if (double.tryParse(filledSize) != null &&
        double.tryParse(avgPrice) != null) {
      return double.parse(filledSize) * double.parse(avgPrice);
    }
    return 0.0;
  }

  // 获取订单总金额
  double get totalAmount {
    if (double.tryParse(size) != null && double.tryParse(price) != null) {
      return double.parse(size) * double.parse(price);
    }
    return 0.0;
  }

  Map<String, dynamic> toJson() {
    return {
      'ordId': orderId,
      'instId': symbol,
      'side': side,
      'ordType': orderType,
      'px': price,
      'avgPx': avgPrice,
      'sz': size,
      'accFillSz': filledSize,
      'state': state,
      'cTime': createTime,
      'uTime': updateTime,
    };
  }
}
