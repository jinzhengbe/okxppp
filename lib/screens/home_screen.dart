import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../api/okx_api.dart';
import '../models/ticker.dart';
import '../services/trading_service.dart';
import '../services/database_service.dart';
import '../widgets/price_card.dart';
import '../widgets/chart_widget.dart';
import '../widgets/order_list.dart';
import '../widgets/ticker_marquee.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_settings_screen.dart';
import 'crypto_list_screen.dart';
import 'news_screen.dart';
import 'news_impact_screen.dart';
import 'database_management_screen.dart';

// 导入全局变量
import '../main.dart';

class HomeScreen extends StatefulWidget {
  final bool useWebSocket;

  const HomeScreen({Key? key, this.useWebSocket = false}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final OkxApi _api = OkxApi();
  final TradingService _tradingService = TradingService();
  final DatabaseService _dbService = DatabaseService();

  late TabController _tabController;
  WebSocketChannel? _tickerChannel;
  StreamSubscription? _tickerSubscription;

  Ticker? _currentTicker;
  List<Ticker> _tickerHistory = [];
  List<String> _logMessages = [];
  bool _isTrading = false;
  final ScrollController _logScrollController = ScrollController();
  Timer? _reconnectTimer;
  Timer? _pollingTimer;
  bool _isLoading = true;
  bool _isConnected = false;

  // 是否尝试使用WebSocket
  late bool _useWebSocket;

  // 添加离线模式变量
  bool _offlineMode = false;

  // 添加模拟价格数据变量
  double _simulatedPrice = 65000.0;
  Timer? _simulationTimer;

  // 添加重连尝试次数变量
  int _reconnectAttempts = 0;

  final String _symbol = dotenv.env['TRADE_SYMBOL'] ?? 'BTC-USDT';

  // 添加代理设置相关变量
  bool _useProxy = false;
  TextEditingController _proxyHostController = TextEditingController();
  TextEditingController _proxyPortController = TextEditingController();

  // 标记是否有轮询请求正在进行中
  bool _isPollingRequestInProgress = false;

  // 添加所有虚拟币的价格数据
  List<Ticker> _allTickers = [];
  Timer? _allTickersPollingTimer;

  @override
  void initState() {
    super.initState();
    // 初始化WebSocket设置
    _useWebSocket = widget.useWebSocket;

    _tabController = TabController(length: 5, vsync: this);

    // 立即获取一次价格数据
    _fetchTickerFallback();

    // 根据设置决定是否尝试连接WebSocket
    if (_useWebSocket) {
      // 尝试连接WebSocket
      _connectWebSocket();
    } else {
      // 使用REST API轮询
      _startPolling();
    }

    // 订阅交易服务的状态更新
    _subscribeToTradingService();

    // 加载代理设置
    _loadProxySettings();

    // 检查是否需要打开代理设置页面
    if (shouldOpenProxySettings) {
      // 重置全局标志
      shouldOpenProxySettings = false;

      // 使用延迟确保UI已经构建完成
      Future.delayed(Duration(milliseconds: 300), () {
        openProxySettings();
      });
    }

    // 设置一个延迟检查，如果5秒后仍未连接成功，则提示用户启用离线模式
    Future.delayed(Duration(seconds: 5), () {
      if (!_isConnected && mounted) {
        _showOfflineModeDialog();
      }
    });

    // 获取所有虚拟币的价格数据
    _fetchAllTickers();
    _startAllTickersPolling();

    // 定期清理旧数据
    _scheduleDataCleaning();
  }

  @override
  void dispose() {
    _disconnectWebSocket();
    _stopPolling();
    _stopSimulation();
    _stopAllTickersPolling();
    _tabController.dispose();
    // 释放TextEditingController
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    super.dispose();
  }

  // 获取所有虚拟币的价格数据
  Future<void> _fetchAllTickers() async {
    try {
      _addLogMessage('获取所有虚拟币价格数据...');

      // 获取所有交易对
      final instruments = await _api.getAllInstruments();

      // 过滤出USDT交易对，并限制数量以避免请求过多
      final symbols = instruments
          .where((i) => i['instId'].toString().endsWith('-USDT'))
          .map((i) => i['instId'].toString())
          .take(50) // 限制为前50个交易对
          .toList();

      // 获取这些交易对的价格数据
      final tickers = await _api.getMultipleTickers(symbols);

      setState(() {
        _allTickers = tickers;
        _isConnected = true;
      });

      _addLogMessage('成功获取${tickers.length}个虚拟币的价格数据');

      // 将数据保存到本地数据库
      await _dbService.saveTickers(tickers);
      _addLogMessage('已将价格数据保存到本地数据库');
    } catch (e) {
      _addLogMessage('获取所有虚拟币价格数据失败: $e');

      // 如果获取失败，尝试从本地数据库加载最新数据
      try {
        final latestTickers = await _dbService.getLatestTickers();
        if (latestTickers.isNotEmpty) {
          final tickers = latestTickers
              .map((data) => Ticker(
                    symbol: data['symbol'],
                    last: data['price'],
                    open24h: '0',
                    high24h: '0',
                    low24h: '0',
                    volCcy24h: data['volume'],
                    vol24h: '0',
                    change24h: '0',
                    changeRate24h: data['change_percentage'],
                    askPx: '0',
                    askSz: '0',
                    bidPx: '0',
                    bidSz: '0',
                    timestamp: data['timestamp'],
                  ))
              .toList();

          setState(() {
            _allTickers = tickers;
          });

          _addLogMessage('已从本地数据库加载${tickers.length}个虚拟币的价格数据');
        }
      } catch (dbError) {
        _addLogMessage('从本地数据库加载价格数据失败: $dbError');
      }
    }
  }

  // 开始轮询获取所有虚拟币的价格数据
  void _startAllTickersPolling() {
    _addLogMessage('开始轮询获取所有虚拟币价格数据');

    // 取消现有的轮询定时器
    _allTickersPollingTimer?.cancel();

    // 设置新的轮询定时器，每30秒获取一次所有价格
    _allTickersPollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchAllTickers();
    });
  }

  // 停止轮询获取所有虚拟币的价格数据
  void _stopAllTickersPolling() {
    _allTickersPollingTimer?.cancel();
    _allTickersPollingTimer = null;
  }

  // 定期清理旧数据
  void _scheduleDataCleaning() {
    // 每天凌晨2点清理一次旧数据
    final now = DateTime.now();
    final nextCleaningTime = DateTime(
      now.year,
      now.month,
      now.day,
      2, // 凌晨2点
      0,
    );

    // 如果当前时间已经过了今天的清理时间，则设置为明天的清理时间
    final cleaningTime = now.isAfter(nextCleaningTime)
        ? nextCleaningTime.add(Duration(days: 1))
        : nextCleaningTime;

    final timeUntilCleaning = cleaningTime.difference(now);

    Timer(timeUntilCleaning, () async {
      // 清理旧数据
      final deletedCount = await _dbService.cleanOldData();
      _addLogMessage('已清理$deletedCount条旧数据');

      // 重新调度下一次清理
      _scheduleDataCleaning();
    });
  }

  // 连接WebSocket获取实时价格
  void _connectWebSocket() {
    try {
      // 添加连接成功日志
      _addLogMessage('正在连接WebSocket...');

      // 尝试创建WebSocket连接
      _tickerChannel = _api.createTickerWebSocket(_symbol);

      _tickerSubscription = _tickerChannel!.stream.listen(
        (data) {
          // 添加数据接收日志
          _addLogMessage('收到WebSocket数据');

          try {
            // 确保数据是字符串
            final String dataStr = data is String ? data : jsonEncode(data);
            final jsonData = jsonDecode(dataStr);

            // 处理心跳响应
            if (jsonData['event'] == 'pong') {
              _addLogMessage('收到心跳响应');
              return;
            }

            // 处理订阅响应
            if (jsonData['event'] == 'subscribe') {
              _addLogMessage('订阅成功: ${jsonData['arg']}');
              setState(() {
                _isConnected = true;
              });
              return;
            }

            // 处理错误消息
            if (jsonData['event'] == 'error') {
              _addLogMessage('WebSocket错误: ${jsonData['msg']}');
              return;
            }

            _addLogMessage(
                '数据解析: ${jsonData.toString().substring(0, min(100, jsonData.toString().length))}...');

            if (jsonData['data'] != null) {
              setState(() {
                _currentTicker = Ticker.fromJson(jsonData['data'][0]);
                _tickerHistory.add(_currentTicker!);

                // 添加价格更新日志
                _addLogMessage('价格更新: ${_currentTicker!.currentPrice}');

                // 限制历史数据长度，避免内存占用过多
                if (_tickerHistory.length > 100) {
                  _tickerHistory.removeAt(0);
                }
              });
            } else {
              _addLogMessage(
                  'WebSocket数据中没有data字段: ${jsonData.toString().substring(0, min(100, jsonData.toString().length))}...');
            }
          } catch (e) {
            _addLogMessage('解析WebSocket数据错误: $e');
          }
        },
        onError: (error) {
          _addLogMessage('WebSocket错误: $error');
          setState(() {
            _isConnected = false;
          });

          // 取消之前的重连计时器
          _reconnectTimer?.cancel();

          // 最多尝试重连3次，避免无限循环
          if (_reconnectAttempts < 3) {
            _reconnectAttempts++;
            _addLogMessage('尝试重新连接 (${_reconnectAttempts}/3)...');
            _reconnectTimer = Timer(const Duration(seconds: 5), () {
              _connectWebSocket();
            });
          } else {
            _addLogMessage('WebSocket连接失败，将使用REST API获取数据');
            _reconnectAttempts = 0;
          }
        },
        onDone: () {
          _addLogMessage('WebSocket连接已关闭');
          setState(() {
            _isConnected = false;
          });

          // 取消之前的重连计时器
          _reconnectTimer?.cancel();

          // 最多尝试重连3次，避免无限循环
          if (_reconnectAttempts < 3) {
            _reconnectAttempts++;
            _addLogMessage('尝试重新连接 (${_reconnectAttempts}/3)...');
            _reconnectTimer = Timer(const Duration(seconds: 5), () {
              _connectWebSocket();
            });
          } else {
            _addLogMessage('WebSocket连接失败，将使用REST API获取数据');
            _reconnectAttempts = 0;
          }
        },
      );
    } catch (e) {
      _addLogMessage('WebSocket连接初始化失败: $e');
      _addLogMessage('将使用REST API获取价格');
      setState(() {
        _isConnected = false;
      });
    }
  }

  // 断开WebSocket连接
  void _disconnectWebSocket() {
    _tickerSubscription?.cancel();
    _tickerChannel?.sink.close();
    _tickerChannel = null;
  }

  // 订阅交易服务的状态更新
  void _subscribeToTradingService() {
    _tradingService.statusStream.listen((message) {
      _addLogMessage(message);
    });
  }

  // 添加日志消息
  void _addLogMessage(String message) {
    setState(() {
      _logMessages.add(
        '${DateFormat('HH:mm:ss').format(DateTime.now())}: $message',
      );

      // 限制日志消息数量
      if (_logMessages.length > 100) {
        _logMessages.removeAt(0);
      }
    });
  }

  // 切换自动交易状态
  void _toggleTrading() async {
    setState(() {
      _isTrading = !_isTrading;
    });

    if (_isTrading) {
      await _tradingService.startTrading();
    } else {
      _tradingService.stopTrading();
    }
  }

  // 手动买入
  void _manualBuy() async {
    if (_currentTicker == null) return;

    final price = _currentTicker!.currentPrice.toString();

    // 如果是离线模式，模拟交易
    if (_offlineMode) {
      _addLogMessage('离线模式: 模拟买入 $_symbol，价格: $price');

      // 显示成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('离线模式: 模拟买入订单已提交'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    try {
      final order = await _api.placeOrder(
        symbol: _symbol,
        side: 'buy',
        orderType: 'limit',
        amount: dotenv.env['TRADE_AMOUNT'] ?? '0.001',
        price: price,
      );

      _addLogMessage('手动买入订单已提交: ${order.orderId}');
    } catch (e) {
      _addLogMessage('手动买入订单提交失败: $e');
    }
  }

  // 手动卖出
  void _manualSell() async {
    if (_currentTicker == null) return;

    final price = _currentTicker!.currentPrice.toString();

    // 如果是离线模式，模拟交易
    if (_offlineMode) {
      _addLogMessage('离线模式: 模拟卖出 $_symbol，价格: $price');

      // 显示成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('离线模式: 模拟卖出订单已提交'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final order = await _api.placeOrder(
        symbol: _symbol,
        side: 'sell',
        orderType: 'limit',
        amount: dotenv.env['TRADE_AMOUNT'] ?? '0.001',
        price: price,
      );

      _addLogMessage('手动卖出订单已提交: ${order.orderId}');
    } catch (e) {
      _addLogMessage('手动卖出订单提交失败: $e');
    }
  }

  // 通过REST API获取价格作为备份
  void _fetchTickerFallback() async {
    try {
      final ticker = await _api.getTicker(_symbol);
      _addLogMessage('通过REST API获取价格: ${ticker.currentPrice}');

      setState(() {
        _currentTicker = ticker;
        _tickerHistory.add(_currentTicker!);
        _isConnected = true; // 更新连接状态为已连接
        _offlineMode = false; // 已连接到服务器，不是离线模式

        // 限制历史数据长度
        if (_tickerHistory.length > 100) {
          _tickerHistory.removeAt(0);
        }
      });
    } catch (e) {
      _addLogMessage('REST API获取价格失败: $e');
      setState(() {
        _isConnected = false; // 更新连接状态为未连接
      });

      // 显示错误提示
      String errorMessage = '连接错误: 无法获取价格数据';
      String errorDetails = '';

      if (e.toString().contains('Operation not permitted')) {
        errorMessage = '网络权限错误: 系统阻止了连接';
        errorDetails = '请检查应用网络权限或使用离线模式';
      } else if (e.toString().contains('Connection refused')) {
        errorMessage = '连接被拒绝: 服务器不可达';
        errorDetails = '请检查网络连接或使用离线模式';
      } else if (e.toString().contains('Connection timed out')) {
        errorMessage = '连接超时: 服务器响应超时';
        errorDetails = '请检查网络连接或使用离线模式';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(errorMessage, style: TextStyle(fontWeight: FontWeight.bold)),
              if (errorDetails.isNotEmpty)
                Text(errorDetails, style: TextStyle(fontSize: 12)),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
          action: SnackBarAction(
            label: '离线模式',
            textColor: Colors.white,
            onPressed: () {
              // 启动离线模式
              _startSimulation();

              // 显示提示
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已启用离线模式，使用模拟数据'),
                  backgroundColor: Colors.blue,
                ),
              );
            },
          ),
        ),
      );
    }
  }

  // 开始REST API轮询
  void _startPolling() {
    _addLogMessage('使用REST API轮询获取价格数据');

    // 取消现有的轮询定时器
    _pollingTimer?.cancel();

    // 设置新的轮询定时器，每1秒获取一次价格
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      // 如果已经有一个请求在进行中，不要发起新的请求
      if (!_isPollingRequestInProgress) {
        _fetchTickerWithRetry();
      } else {
        _addLogMessage('上一次请求尚未完成，跳过本次轮询');
      }
    });
  }

  // 停止REST API轮询
  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // 带有重试机制的获取价格方法
  void _fetchTickerWithRetry({int retryCount = 0}) async {
    if (retryCount >= 3) {
      _addLogMessage('达到最大重试次数，放弃本次请求');
      _isPollingRequestInProgress = false;
      return;
    }

    _isPollingRequestInProgress = true;
    try {
      // 调用_fetchTickerFallback方法，但不使用其返回值
      _fetchTickerFallback();
      _isPollingRequestInProgress = false;
    } catch (e) {
      _addLogMessage('获取价格失败，尝试重试 (${retryCount + 1}/3): $e');

      // 使用指数退避策略，每次重试等待时间增加
      final waitTime = 300 * pow(2, retryCount).toInt();
      await Future.delayed(Duration(milliseconds: waitTime));

      _fetchTickerWithRetry(retryCount: retryCount + 1);
    }
  }

  // 启动模拟数据生成
  void _startSimulation() {
    _addLogMessage('启动离线模式，使用模拟数据');

    // 取消现有的模拟定时器
    _simulationTimer?.cancel();

    // 初始化模拟价格（接近当前比特币价格，带有随机波动）
    _simulatedPrice = 65000.0 + (Random().nextDouble() * 2000 - 1000);

    // 创建初始的模拟Ticker
    final now = DateTime.now();
    final simulatedTicker = Ticker(
      symbol: _symbol,
      last: _simulatedPrice.toStringAsFixed(2),
      open24h: (_simulatedPrice * 0.99).toStringAsFixed(2),
      high24h: (_simulatedPrice * 1.01).toStringAsFixed(2),
      low24h: (_simulatedPrice * 0.98).toStringAsFixed(2),
      volCcy24h: (1000 + Random().nextDouble() * 500).toStringAsFixed(2),
      vol24h: '1000',
      change24h: '0',
      changeRate24h: '0',
      askPx: (_simulatedPrice * 1.001).toStringAsFixed(2),
      askSz: '1',
      bidPx: (_simulatedPrice * 0.999).toStringAsFixed(2),
      bidSz: '1',
      timestamp: now.millisecondsSinceEpoch.toString(),
    );

    setState(() {
      _currentTicker = simulatedTicker;
      _tickerHistory.add(_currentTicker!);
      _isConnected = true; // 在离线模式中，我们假装已连接
    });

    // 设置模拟定时器，每2秒更新一次价格
    _simulationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      // 生成-0.5%到+0.5%之间的随机价格变化
      double changePercent = (Random().nextDouble() - 0.5) * 1.0;

      // 有10%的概率产生更大的波动（-2%到+2%）
      if (Random().nextDouble() < 0.1) {
        changePercent = (Random().nextDouble() - 0.5) * 4.0;
        _addLogMessage('模拟市场波动: 价格大幅${changePercent > 0 ? "上涨" : "下跌"}');
      }

      // 计算新价格
      _simulatedPrice = _simulatedPrice * (1 + changePercent / 100);

      // 计算价格变化
      double lastPrice = _currentTicker!.currentPrice;
      double priceChange = _simulatedPrice - lastPrice;
      double changeRate = priceChange / lastPrice;

      // 创建新的模拟Ticker
      final now = DateTime.now();
      final simulatedTicker = Ticker(
        symbol: _symbol,
        last: _simulatedPrice.toStringAsFixed(2),
        open24h: _tickerHistory.first.last,
        high24h:
            max(_simulatedPrice, _currentTicker!.highPrice).toStringAsFixed(2),
        low24h:
            min(_simulatedPrice, _currentTicker!.lowPrice).toStringAsFixed(2),
        volCcy24h: (_currentTicker!.volume + Random().nextDouble() * 50)
            .toStringAsFixed(2),
        vol24h:
            (double.parse(_currentTicker!.vol24h) + Random().nextDouble() * 10)
                .toStringAsFixed(2),
        change24h: priceChange.toStringAsFixed(2),
        changeRate24h: changeRate.toStringAsFixed(6),
        askPx: (_simulatedPrice * 1.001).toStringAsFixed(2),
        askSz: '1',
        bidPx: (_simulatedPrice * 0.999).toStringAsFixed(2),
        bidSz: '1',
        timestamp: now.millisecondsSinceEpoch.toString(),
      );

      setState(() {
        _currentTicker = simulatedTicker;
        _tickerHistory.add(_currentTicker!);

        // 限制历史数据长度
        if (_tickerHistory.length > 100) {
          _tickerHistory.removeAt(0);
        }
      });

      _addLogMessage('模拟价格更新: ${_simulatedPrice.toStringAsFixed(2)}');
    });
  }

  // 停止模拟数据生成
  void _stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
  }

  // 切换数据获取模式
  void _toggleDataMode() {
    setState(() {
      _useWebSocket = !_useWebSocket;
    });

    if (_useWebSocket) {
      _addLogMessage('切换到WebSocket模式');
      _stopPolling();
      _connectWebSocket();
    } else {
      _addLogMessage('切换到REST API轮询模式');
      _disconnectWebSocket();
      _startPolling();
    }
  }

  // 打开代理设置页面
  void openProxySettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NetworkSettingsScreen(),
      ),
    );

    // 添加日志
    _addLogMessage('已打开网络设置页面');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('OKX交易机器人 - $_symbol'),
        actions: [
          // 添加网络设置按钮
          IconButton(
            icon: const Icon(Icons.network_check),
            tooltip: '网络设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NetworkSettingsScreen(),
                ),
              );
            },
          ),
          // 添加虚拟币列表按钮
          IconButton(
            icon: const Icon(Icons.currency_bitcoin),
            tooltip: '虚拟币列表',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CryptoListScreen(),
                ),
              );
            },
          ),
          // 添加新闻影响分析按钮
          IconButton(
            icon: const Icon(Icons.newspaper),
            tooltip: '新闻影响分析',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NewsImpactScreen(),
                ),
              );
            },
          ),
          // 添加数据库管理按钮
          IconButton(
            icon: const Icon(Icons.storage),
            tooltip: '数据库管理',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DatabaseManagementScreen(),
                ),
              );
            },
          ),
          // WebSocket/REST切换开关
          Switch(
            value: _useWebSocket,
            onChanged: (value) {
              setState(() {
                _useWebSocket = value;
                if (_useWebSocket) {
                  _startWebSocketConnection();
                } else {
                  _closeWebSocketConnection();
                  _startPolling();
                }
              });
            },
            activeColor: Colors.green,
            inactiveTrackColor: Colors.blue.withOpacity(0.5),
            activeThumbImage: const AssetImage('assets/websocket_icon.png'),
            inactiveThumbImage: const AssetImage('assets/rest_icon.png'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.show_chart), text: '行情'),
            Tab(icon: Icon(Icons.receipt_long), text: '订单'),
            Tab(icon: Icon(Icons.article), text: '新闻'),
            Tab(icon: Icon(Icons.history), text: '日志'),
            Tab(icon: Icon(Icons.settings), text: '设置'),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
      ),
      body: Column(
        children: [
          // 添加虚拟币价格滚动显示
          if (_allTickers.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: TickerMarquee(
                tickers: _allTickers,
                height: 40,
                speed: 30.0,
              ),
            ),

          // 价格卡片
          if (_currentTicker != null) PriceCard(ticker: _currentTicker!),

          // 主要内容区域
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 行情页面
                _buildMarketTab(),

                // 订单页面
                OrderList(symbol: _symbol),

                // 新闻页面
                const NewsScreen(),

                // 日志页面
                _buildLogTab(),

                // 设置页面
                _buildSettingsPanel(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _manualBuy,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('买入'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _manualSell,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('卖出'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建行情页面
  Widget _buildMarketTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 添加离线模式指示器
          if (_offlineMode)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: Row(
                children: [
                  Icon(Icons.offline_bolt, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '离线模式',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[800],
                          ),
                        ),
                        Text(
                          '当前使用模拟数据，价格仅供参考',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      // 尝试重新连接
                      setState(() {
                        _offlineMode = false;
                      });
                      _stopSimulation();
                      if (_useWebSocket) {
                        _connectWebSocket();
                      } else {
                        _startPolling();
                      }
                    },
                    child: Text('尝试连接'),
                  ),
                ],
              ),
            ),

          SizedBox(height: 16),

          const Text(
            '价格走势',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // 价格图表
          Expanded(
            child: _tickerHistory.length > 1
                ? ChartWidget(tickerHistory: _tickerHistory)
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _isConnected
                            ? CircularProgressIndicator()
                            : Icon(Icons.error_outline,
                                color: Colors.red, size: 48),
                        SizedBox(height: 16),
                        Text(
                          _isConnected ? '正在加载价格数据...' : '连接错误: 无法获取价格数据',
                          style: TextStyle(
                            color: _isConnected ? Colors.black : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!_isConnected) ...[
                          SizedBox(height: 8),
                          Container(
                            width: 300,
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.red.withOpacity(0.3)),
                            ),
                            child: Column(
                              children: [
                                Text('可能的原因:'),
                                SizedBox(height: 4),
                                Text('1. 系统阻止了网络连接 (Operation not permitted)'),
                                Text('2. 网络连接不可用或不稳定'),
                                Text('3. OKX服务器暂时不可达'),
                                SizedBox(height: 8),
                                Text('解决方案:'),
                                SizedBox(height: 4),
                                Text('1. 配置代理服务器 (推荐)'),
                                Text('2. 使用VPN服务'),
                                Text('3. 检查macOS网络权限设置'),
                              ],
                            ),
                          ),
                          SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed: () {
                                  if (_useWebSocket) {
                                    _disconnectWebSocket();
                                    _connectWebSocket();
                                  } else {
                                    _fetchTickerFallback();
                                  }
                                },
                                child: Text('重试连接'),
                              ),
                              SizedBox(width: 16),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          NetworkSettingsScreen(),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                                child: Text('网络设置'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
          ),

          const SizedBox(height: 16),

          // 交易配置信息
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '交易配置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('交易对: $_symbol'),
                  Text('交易数量: ${dotenv.env['TRADE_AMOUNT'] ?? '0.001'}'),
                  Text('买入阈值: ${dotenv.env['BUY_THRESHOLD'] ?? '30000'}'),
                  Text('卖出阈值: ${dotenv.env['SELL_THRESHOLD'] ?? '32000'}'),
                  Text('每日最大交易次数: ${dotenv.env['MAX_TRADES_PER_DAY'] ?? '5'}'),
                  Text('止损百分比: ${dotenv.env['STOP_LOSS_PERCENTAGE'] ?? '2'}%'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建日志页面
  Widget _buildLogTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '操作日志',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  // 添加测试连接按钮
                  IconButton(
                    icon: const Icon(Icons.network_check),
                    tooltip: '测试连接',
                    onPressed: _testConnection,
                  ),
                  // 添加复制按钮
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: '复制日志',
                    onPressed: _copyLogs,
                  ),
                  // 原有的删除按钮
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: '清除日志',
                    onPressed: () {
                      setState(() {
                        _logMessages.clear();
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: _logScrollController,
              itemCount: _logMessages.length,
              itemBuilder: (context, index) {
                final message = _logMessages[_logMessages.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(message),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 测试连接
  void _testConnection() async {
    _addLogMessage('开始测试连接...');

    // 测试REST API连接
    try {
      _addLogMessage('测试REST API连接...');
      final ticker = await _api.getTicker(_symbol);
      _addLogMessage('REST API连接成功，当前价格: ${ticker.currentPrice}');
    } catch (e) {
      _addLogMessage('REST API连接失败: $e');
    }

    // 测试WebSocket连接
    _addLogMessage('测试WebSocket连接...');
    _addLogMessage('当前WebSocket连接状态: ${_isConnected ? "已连接" : "未连接"}');

    if (_useWebSocket && !_isConnected) {
      _addLogMessage('尝试重新连接WebSocket...');
      _disconnectWebSocket();
      _connectWebSocket();
    }

    // 显示网络环境信息
    _addLogMessage('网络环境信息:');
    _addLogMessage(
        'HTTP_PROXY: ${Platform.environment['HTTP_PROXY'] ?? Platform.environment['http_proxy'] ?? "未设置"}');
    _addLogMessage(
        'HTTPS_PROXY: ${Platform.environment['HTTPS_PROXY'] ?? Platform.environment['https_proxy'] ?? "未设置"}');

    // 执行详细的网络诊断
    _runNetworkDiagnostics();

    _addLogMessage('连接测试完成');
  }

  // 运行详细的网络诊断
  void _runNetworkDiagnostics() async {
    _addLogMessage('开始详细网络诊断...');

    // 测试DNS解析
    _addLogMessage('测试DNS解析...');
    final hosts = [
      'www.okx.com',
      'aws.okx.com',
      'wsaws.okx.com',
    ];

    for (final host in hosts) {
      try {
        final addresses = await InternetAddress.lookup(host);
        _addLogMessage(
            'DNS解析 $host 成功: ${addresses.map((a) => a.address).join(', ')}');
      } catch (e) {
        _addLogMessage('DNS解析 $host 失败: $e');
      }
    }

    // 测试HTTP连接
    _addLogMessage('测试HTTP连接...');
    final urls = [
      'https://www.okx.com',
      'https://aws.okx.com',
    ];

    for (final url in urls) {
      try {
        final httpClient = HttpClient();
        httpClient.connectionTimeout = const Duration(seconds: 5);

        final request = await httpClient.getUrl(Uri.parse(url));
        final response = await request.close();

        _addLogMessage('HTTP连接 $url 成功，状态码: ${response.statusCode}');
        httpClient.close();
      } catch (e) {
        _addLogMessage('HTTP连接 $url 失败: $e');
      }
    }

    // 测试WebSocket端口
    _addLogMessage('测试WebSocket端口...');
    final wsTests = [
      {'host': 'wsaws.okx.com', 'port': 8443},
      {'host': 'ws.okx.com', 'port': 8443},
    ];

    for (final test in wsTests) {
      try {
        _addLogMessage('尝试连接到 ${test['host']}:${test['port']}...');

        // 使用Socket API测试端口连接
        final socket = await Socket.connect(
          test['host'] as String,
          test['port'] as int,
          timeout: const Duration(seconds: 5),
        );

        _addLogMessage('Socket连接到 ${test['host']}:${test['port']} 成功');
        socket.destroy();
      } catch (e) {
        _addLogMessage('Socket连接到 ${test['host']}:${test['port']} 失败: $e');

        if (e.toString().contains('Operation not permitted')) {
          _addLogMessage('⚠️ 检测到系统权限问题，可能需要检查应用程序网络权限或使用VPN');
        } else if (e.toString().contains('Connection refused')) {
          _addLogMessage('⚠️ 连接被拒绝，服务器可能拒绝了连接请求');
        } else if (e.toString().contains('Connection timed out')) {
          _addLogMessage('⚠️ 连接超时，可能是网络问题或防火墙阻止');
        }
      }
    }

    // 提供解决建议
    _addLogMessage('诊断完成，建议:');
    _addLogMessage('1. 如果DNS解析成功但连接失败，可能是网络权限问题');
    _addLogMessage('2. 考虑使用VPN服务');
    _addLogMessage('3. 检查macOS的应用程序网络权限');
    _addLogMessage('4. 如果REST API工作但WebSocket不工作，建议使用REST API模式');
  }

  // 复制日志内容到剪贴板
  void _copyLogs() async {
    if (_logMessages.isEmpty) {
      // 如果没有日志，显示提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有日志可复制')),
      );
      return;
    }

    // 将所有日志合并为一个字符串，按时间倒序排列
    final String logText = _logMessages.join('\n');

    // 复制到剪贴板
    await Clipboard.setData(ClipboardData(text: logText));

    // 显示成功提示
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('日志已复制到剪贴板')),
    );
  }

  // 构建设置面板
  Widget _buildSettingsPanel() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '应用设置',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // 网络设置卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '网络设置',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton.icon(
                        icon: Icon(Icons.open_in_new),
                        label: Text('打开网络设置'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => NetworkSettingsScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('配置网络连接、代理设置和网络诊断'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 离线模式设置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '离线模式',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('使用模拟数据'),
                          Text(
                            '在无法连接服务器时使用',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      Switch(
                        value: _offlineMode,
                        onChanged: (value) {
                          setState(() {
                            _offlineMode = value;
                          });

                          if (_offlineMode) {
                            // 停止其他连接方式
                            _disconnectWebSocket();
                            _stopPolling();
                            // 启动模拟数据
                            _startSimulation();
                            _addLogMessage('已启用离线模式，使用模拟数据');
                          } else {
                            // 停止模拟数据
                            _stopSimulation();
                            // 根据设置启动连接
                            if (_useWebSocket) {
                              _connectWebSocket();
                            } else {
                              _startPolling();
                            }
                            _addLogMessage('已禁用离线模式，尝试连接服务器');
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _offlineMode ? '当前使用模拟数据，价格仅供参考' : '当前尝试连接真实服务器',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _offlineMode ? Colors.amber[800] : Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 数据获取模式设置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '数据获取模式',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WebSocket模式 (实时数据)'),
                          Text(
                            '需要稳定的网络连接，可能受系统限制',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      Switch(
                        value: _useWebSocket,
                        onChanged: (value) {
                          _toggleDataMode();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _useWebSocket
                        ? '当前模式: WebSocket (实时数据)'
                        : '当前模式: REST API (轮询)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _useWebSocket ? Colors.blue : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 交易设置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '交易设置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('自动交易'),
                      Switch(
                        value: _isTrading,
                        onChanged: (_) => _toggleTrading(),
                      ),
                    ],
                  ),
                  Text(
                    _isTrading ? '自动交易已启用' : '自动交易已禁用',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _isTrading ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 日志设置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '日志设置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: Icon(Icons.delete),
                        label: Text('清除日志'),
                        onPressed: _clearLogs,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      SizedBox(width: 16),
                      ElevatedButton.icon(
                        icon: Icon(Icons.copy),
                        label: Text('复制日志'),
                        onPressed: _copyLogs,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 保存代理设置
  void _saveProxySettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_proxy', _useProxy);

    if (_useProxy) {
      await prefs.setString('proxy_host', _proxyHostController.text);
      await prefs.setString('proxy_port', _proxyPortController.text);

      // 设置环境变量
      final proxyUrl =
          'http://${_proxyHostController.text}:${_proxyPortController.text}';
      Platform.environment['HTTP_PROXY'] = proxyUrl;
      Platform.environment['HTTPS_PROXY'] = proxyUrl;

      _addLogMessage('已保存代理设置: $proxyUrl');
    } else {
      // 清除环境变量
      Platform.environment['HTTP_PROXY'] = '';
      Platform.environment['HTTPS_PROXY'] = '';

      _addLogMessage('已禁用代理');
    }
  }

  // 加载代理设置
  void _loadProxySettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useProxy = prefs.getBool('use_proxy') ?? false;
      _proxyHostController.text = prefs.getString('proxy_host') ?? '127.0.0.1';
      _proxyPortController.text = prefs.getString('proxy_port') ?? '7890';
    });

    if (_useProxy) {
      // 设置环境变量
      final proxyUrl =
          'http://${_proxyHostController.text}:${_proxyPortController.text}';
      Platform.environment['HTTP_PROXY'] = proxyUrl;
      Platform.environment['HTTPS_PROXY'] = proxyUrl;

      _addLogMessage('已加载代理设置: $proxyUrl');
    }
  }

  // 测试代理连接
  void _testProxyConnection() async {
    if (!_useProxy) {
      _addLogMessage('请先启用代理');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请先启用代理设置'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final proxyHost = _proxyHostController.text;
    final proxyPort = int.tryParse(_proxyPortController.text) ?? 0;

    if (proxyHost.isEmpty || proxyPort <= 0) {
      _addLogMessage('代理设置无效');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('代理设置无效，请输入正确的服务器地址和端口'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _addLogMessage('测试代理连接: $proxyHost:$proxyPort');

    // 显示进度指示器
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('测试代理连接'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在测试代理连接...\n$proxyHost:$proxyPort'),
            ],
          ),
        );
      },
    );

    bool proxyConnected = false;
    bool okxConnected = false;
    String errorMessage = '';

    try {
      // 测试代理连接
      final socket = await Socket.connect(proxyHost, proxyPort,
          timeout: const Duration(seconds: 3));
      _addLogMessage('代理连接成功');
      proxyConnected = true;
      socket.destroy();

      // 测试通过代理访问OKX
      _addLogMessage('测试通过代理访问OKX...');

      final client = HttpClient();
      client.findProxy = (uri) => 'PROXY $proxyHost:$proxyPort';
      client.connectionTimeout = const Duration(seconds: 5);
      client.badCertificateCallback = (cert, host, port) => true;

      try {
        final request = await client.getUrl(Uri.parse('https://www.okx.com'));
        final response = await request.close();

        _addLogMessage('通过代理访问OKX成功，状态码: ${response.statusCode}');
        okxConnected = true;
        client.close();
      } catch (e) {
        _addLogMessage('通过代理访问OKX失败: $e');
        errorMessage = '代理可连接，但无法访问OKX: ${e.toString().split('\n')[0]}';
        client.close();
      }

      // 关闭进度对话框
      Navigator.of(context).pop();

      // 显示测试结果
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              okxConnected ? '代理测试成功' : '代理测试部分成功',
              style: TextStyle(
                color: okxConnected ? Colors.green : Colors.orange,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('代理服务器: $proxyHost:$proxyPort'),
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      proxyConnected ? Icons.check_circle : Icons.error,
                      color: proxyConnected ? Colors.green : Colors.red,
                    ),
                    SizedBox(width: 8),
                    Text('代理服务器连接'),
                  ],
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      okxConnected ? Icons.check_circle : Icons.error,
                      color: okxConnected ? Colors.green : Colors.red,
                    ),
                    SizedBox(width: 8),
                    Text('通过代理访问OKX'),
                  ],
                ),
                if (errorMessage.isNotEmpty) ...[
                  SizedBox(height: 8),
                  Text(
                    errorMessage,
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('关闭'),
              ),
              if (okxConnected)
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // 重新连接WebSocket
                    if (_useWebSocket) {
                      _disconnectWebSocket();
                      _connectWebSocket();
                    } else {
                      _fetchTickerFallback();
                    }
                  },
                  child: Text('应用并重新连接'),
                ),
            ],
          );
        },
      );

      // 如果代理测试成功，更新环境变量
      if (proxyConnected) {
        final proxyUrl = 'http://$proxyHost:$proxyPort';
        Platform.environment['HTTP_PROXY'] = proxyUrl;
        Platform.environment['HTTPS_PROXY'] = proxyUrl;
        _addLogMessage('已更新代理环境变量: $proxyUrl');
      }
    } catch (e) {
      // 关闭进度对话框
      Navigator.of(context).pop();

      _addLogMessage('代理连接测试失败: $e');

      // 显示错误对话框
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('代理测试失败', style: TextStyle(color: Colors.red)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('无法连接到代理服务器: $proxyHost:$proxyPort'),
                SizedBox(height: 8),
                Text(
                  '错误信息: ${e.toString().split('\n')[0]}',
                  style: TextStyle(fontSize: 12),
                ),
                SizedBox(height: 16),
                Text('可能的原因:'),
                Text('1. 代理服务器未运行'),
                Text('2. 代理地址或端口错误'),
                Text('3. 代理服务器拒绝连接'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('关闭'),
              ),
            ],
          );
        },
      );
    }
  }

  // 清除日志
  void _clearLogs() {
    setState(() {
      _logMessages.clear();
    });
  }

  // 显示离线模式对话框
  void _showOfflineModeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('离线模式提示'),
          content: Text('当前无法连接到服务器，是否启用离线模式？'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startSimulation();
              },
              child: Text('启用离线模式'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('取消'),
            ),
          ],
        );
      },
    );
  }

  // WebSocket相关方法
  void _startWebSocketConnection() {
    setState(() {
      _isConnected = true;
    });

    // 这里应该实现WebSocket连接逻辑
    print('启动WebSocket连接');

    // 停止轮询
    _stopPolling();

    // 订阅行情数据
    _subscribeToTicker();
  }

  void _closeWebSocketConnection() {
    setState(() {
      _isConnected = false;
    });

    // 这里应该实现关闭WebSocket连接的逻辑
    print('关闭WebSocket连接');
  }

  void _subscribeToTicker() {
    // 这里应该实现订阅行情数据的逻辑
    print('订阅$_symbol行情数据');
  }
}
