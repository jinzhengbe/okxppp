import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../api/okx_api.dart';
import '../models/ticker.dart';
import '../models/order.dart';

class TradingService {
  final OkxApi _api = OkxApi();
  late final String _symbol;
  late final double _tradeAmount;
  late final double _buyThreshold;
  late final double _sellThreshold;
  late final int _maxTradesPerDay;
  late final double _stopLossPercentage;

  WebSocketChannel? _tickerChannel;
  StreamSubscription? _tickerSubscription;

  // 交易状态
  bool _isTrading = false;
  int _todayTradeCount = 0;
  DateTime _lastTradeTime = DateTime.now().subtract(const Duration(days: 1));
  List<Order> _recentOrders = [];

  // 流控制器
  final _tickerStreamController = StreamController<Ticker>.broadcast();
  final _ordersStreamController = StreamController<List<Order>>.broadcast();
  final _statusStreamController = StreamController<String>.broadcast();

  // 公开的流
  Stream<Ticker> get tickerStream => _tickerStreamController.stream;
  Stream<List<Order>> get ordersStream => _ordersStreamController.stream;
  Stream<String> get statusStream => _statusStreamController.stream;

  // 单例模式
  static final TradingService _instance = TradingService._internal();

  factory TradingService() {
    return _instance;
  }

  TradingService._internal() {
    _loadConfig();
  }

  // 加载配置
  void _loadConfig() {
    _symbol = dotenv.env['TRADE_SYMBOL'] ?? 'BTC-USDT';
    _tradeAmount =
        double.tryParse(dotenv.env['TRADE_AMOUNT'] ?? '0.001') ?? 0.001;
    _buyThreshold =
        double.tryParse(dotenv.env['BUY_THRESHOLD'] ?? '30000') ?? 30000;
    _sellThreshold =
        double.tryParse(dotenv.env['SELL_THRESHOLD'] ?? '32000') ?? 32000;
    _maxTradesPerDay =
        int.tryParse(dotenv.env['MAX_TRADES_PER_DAY'] ?? '5') ?? 5;
    _stopLossPercentage =
        double.tryParse(dotenv.env['STOP_LOSS_PERCENTAGE'] ?? '2') ?? 2;
  }

  // 启动交易服务
  Future<void> startTrading() async {
    if (_isTrading) return;

    _isTrading = true;
    _logStatus('交易服务已启动');

    // 重置每日交易计数（如果是新的一天）
    _resetDailyTradeCount();

    // 获取最近订单
    await _fetchRecentOrders();

    // 启动WebSocket连接获取实时价格
    _connectToTickerWebSocket();
  }

  // 停止交易服务
  void stopTrading() {
    if (!_isTrading) return;

    _isTrading = false;
    _disconnectWebSocket();
    _logStatus('交易服务已停止');
  }

  // 连接到WebSocket获取实时价格
  void _connectToTickerWebSocket() {
    _tickerChannel = _api.createTickerWebSocket(_symbol);

    _tickerSubscription = _tickerChannel!.stream.listen(
      (data) {
        final jsonData = jsonDecode(data);

        if (jsonData['data'] != null) {
          final ticker = Ticker.fromJson(jsonData['data'][0]);
          _tickerStreamController.add(ticker);

          // 执行交易策略
          if (_isTrading) {
            _executeStrategy(ticker);
          }
        }
      },
      onError: (error) {
        _logStatus('WebSocket错误: $error');
        // 尝试重新连接
        Future.delayed(const Duration(seconds: 5), _connectToTickerWebSocket);
      },
      onDone: () {
        _logStatus('WebSocket连接已关闭');
        // 尝试重新连接
        if (_isTrading) {
          Future.delayed(const Duration(seconds: 5), _connectToTickerWebSocket);
        }
      },
    );
  }

  // 断开WebSocket连接
  void _disconnectWebSocket() {
    _tickerSubscription?.cancel();
    _tickerChannel?.sink.close();
    _tickerChannel = null;
  }

  // 获取最近订单
  Future<void> _fetchRecentOrders() async {
    try {
      _recentOrders = await _api.getOrderHistory(_symbol);
      _ordersStreamController.add(_recentOrders);
    } catch (e) {
      _logStatus('获取订单历史失败: $e');
    }
  }

  // 执行交易策略
  void _executeStrategy(Ticker ticker) async {
    // 检查是否超过每日交易限制
    if (_todayTradeCount >= _maxTradesPerDay) {
      return;
    }

    final currentPrice = ticker.currentPrice;

    // 简单策略：价格低于阈值买入，高于阈值卖出
    if (currentPrice < _buyThreshold) {
      _logStatus('价格低于$_buyThreshold，准备买入');
      await _placeBuyOrder(currentPrice.toString());
    } else if (currentPrice > _sellThreshold) {
      _logStatus('价格高于$_sellThreshold，准备卖出');
      await _placeSellOrder(currentPrice.toString());
    }

    // 止损策略
    await _checkStopLoss(currentPrice);
  }

  // 下买单
  Future<void> _placeBuyOrder(String price) async {
    try {
      final order = await _api.placeOrder(
        symbol: _symbol,
        side: 'buy',
        orderType: 'limit',
        amount: _tradeAmount.toString(),
        price: price,
      );

      _logStatus('买入订单已提交: ${order.orderId}');
      _updateTradeCount();
      await _fetchRecentOrders();
    } catch (e) {
      _logStatus('买入订单提交失败: $e');
    }
  }

  // 下卖单
  Future<void> _placeSellOrder(String price) async {
    try {
      final order = await _api.placeOrder(
        symbol: _symbol,
        side: 'sell',
        orderType: 'limit',
        amount: _tradeAmount.toString(),
        price: price,
      );

      _logStatus('卖出订单已提交: ${order.orderId}');
      _updateTradeCount();
      await _fetchRecentOrders();
    } catch (e) {
      _logStatus('卖出订单提交失败: $e');
    }
  }

  // 检查止损
  Future<void> _checkStopLoss(double currentPrice) async {
    // 获取最近的买入订单
    final recentBuyOrders =
        _recentOrders
            .where(
              (order) =>
                  order.side == 'buy' &&
                  order.isSuccessful &&
                  double.tryParse(order.avgPrice) != null,
            )
            .toList();

    if (recentBuyOrders.isEmpty) return;

    // 按时间排序，获取最近的买入订单
    recentBuyOrders.sort(
      (a, b) => int.parse(b.createTime).compareTo(int.parse(a.createTime)),
    );

    final latestBuyOrder = recentBuyOrders.first;
    final buyPrice = double.parse(latestBuyOrder.avgPrice);

    // 计算价格下跌百分比
    final priceDrop = (buyPrice - currentPrice) / buyPrice * 100;

    // 如果价格下跌超过止损百分比，执行卖出
    if (priceDrop > _stopLossPercentage) {
      _logStatus('触发止损: 买入价 $buyPrice, 当前价 $currentPrice, 下跌 $priceDrop%');
      await _placeSellOrder(currentPrice.toString());
    }
  }

  // 更新交易计数
  void _updateTradeCount() {
    _todayTradeCount++;
    _lastTradeTime = DateTime.now();
  }

  // 重置每日交易计数
  void _resetDailyTradeCount() {
    final now = DateTime.now();
    final lastTradeDate = DateTime(
      _lastTradeTime.year,
      _lastTradeTime.month,
      _lastTradeTime.day,
    );
    final today = DateTime(now.year, now.month, now.day);

    if (lastTradeDate.isBefore(today)) {
      _todayTradeCount = 0;
    }
  }

  // 记录状态
  void _logStatus(String message) {
    print(message);
    _statusStreamController.add(message);
  }

  // 释放资源
  void dispose() {
    _disconnectWebSocket();
    _tickerStreamController.close();
    _ordersStreamController.close();
    _statusStreamController.close();
  }
}
