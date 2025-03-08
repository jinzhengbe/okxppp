import 'dart:async';
import 'dart:math';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../api/okx_api.dart';
import '../models/price_data.dart';
import '../models/trade_data.dart';
import '../models/orderbook_data.dart';
import '../models/sentiment_data.dart';
import 'influxdb_service.dart';
import 'postgres_service.dart';
import 'advanced_news_service.dart';

class CryptoDataCollectionService {
  static final CryptoDataCollectionService _instance =
      CryptoDataCollectionService._internal();

  final OkxApi _okxApi = OkxApi();
  final InfluxDBService _influxDBService = InfluxDBService();
  final PostgresService _postgresService = PostgresService();
  final AdvancedNewsService _advancedNewsService = AdvancedNewsService();

  // 定时器
  Timer? _priceCollectionTimer;
  Timer? _orderBookCollectionTimer;
  Timer? _tradeCollectionTimer;
  Timer? _sentimentCollectionTimer;
  Timer? _dataAggregationTimer;

  // 收集状态
  bool _isCollectingPrices = false;
  bool _isCollectingOrderBooks = false;
  bool _isCollectingTrades = false;
  bool _isCollectingSentiment = false;

  // 单例模式
  factory CryptoDataCollectionService() {
    return _instance;
  }

  CryptoDataCollectionService._internal();

  // 启动所有数据收集
  Future<void> startAllDataCollection() async {
    await startPriceDataCollection();
    await startOrderBookDataCollection();
    await startTradeDataCollection();
    await startSentimentDataCollection();
    startDataAggregation();
  }

  // 停止所有数据收集
  void stopAllDataCollection() {
    stopPriceDataCollection();
    stopOrderBookDataCollection();
    stopTradeDataCollection();
    stopSentimentDataCollection();
    stopDataAggregation();
  }

  // 启动价格数据收集
  Future<void> startPriceDataCollection(
      {Duration interval = const Duration(minutes: 1)}) async {
    if (_isCollectingPrices) return;

    _isCollectingPrices = true;
    print('开始收集价格数据，间隔: ${interval.inSeconds}秒');

    // 立即收集一次
    await collectPriceData();

    // 设置定时器
    _priceCollectionTimer = Timer.periodic(interval, (_) async {
      await collectPriceData();
    });
  }

  // 停止价格数据收集
  void stopPriceDataCollection() {
    _priceCollectionTimer?.cancel();
    _priceCollectionTimer = null;
    _isCollectingPrices = false;
    print('已停止价格数据收集');
  }

  // 收集价格数据
  Future<void> collectPriceData() async {
    try {
      print('正在收集价格数据...');

      // 获取要收集的交易对列表
      final symbols = await _getSymbolsToCollect();

      // 批量获取价格数据
      final tickers = await _okxApi.getMultipleTickers(symbols);

      // 转换为PriceData对象
      final priceDataList =
          tickers.map((ticker) => PriceData.fromTicker(ticker, 'OKX')).toList();

      // 保存到InfluxDB
      await _influxDBService.savePriceDataBatch(priceDataList);

      print('成功收集并保存了${priceDataList.length}条价格数据');
    } catch (e) {
      print('收集价格数据失败: $e');
    }
  }

  // 启动订单簿数据收集
  Future<void> startOrderBookDataCollection(
      {Duration interval = const Duration(minutes: 5)}) async {
    if (_isCollectingOrderBooks) return;

    _isCollectingOrderBooks = true;
    print('开始收集订单簿数据，间隔: ${interval.inSeconds}秒');

    // 立即收集一次
    await collectOrderBookData();

    // 设置定时器
    _orderBookCollectionTimer = Timer.periodic(interval, (_) async {
      await collectOrderBookData();
    });
  }

  // 停止订单簿数据收集
  void stopOrderBookDataCollection() {
    _orderBookCollectionTimer?.cancel();
    _orderBookCollectionTimer = null;
    _isCollectingOrderBooks = false;
    print('已停止订单簿数据收集');
  }

  // 收集订单簿数据
  Future<void> collectOrderBookData() async {
    try {
      print('正在收集订单簿数据...');

      // 获取要收集的交易对列表（限制数量，避免请求过多）
      final symbols = (await _getSymbolsToCollect()).take(10).toList();

      for (final symbol in symbols) {
        try {
          // 获取订单簿数据
          final orderBook = await _okxApi.getOrderBook(symbol);

          // 转换为OrderBookData对象
          final orderBookData = OrderBookData(
            timestamp: DateTime.now(),
            symbol: symbol,
            exchange: 'OKX',
            bids: orderBook.bids
                .map((bid) => OrderBookEntry(
                      price: double.parse(bid[0]),
                      amount: double.parse(bid[1]),
                    ))
                .toList(),
            asks: orderBook.asks
                .map((ask) => OrderBookEntry(
                      price: double.parse(ask[0]),
                      amount: double.parse(ask[1]),
                    ))
                .toList(),
          );

          // 保存到InfluxDB
          await _influxDBService.saveOrderBookData(orderBookData);

          print('成功收集并保存了$symbol的订单簿数据');

          // 添加延迟，避免请求过于频繁
          await Future.delayed(const Duration(seconds: 1));
        } catch (e) {
          print('收集$symbol订单簿数据失败: $e');
        }
      }
    } catch (e) {
      print('收集订单簿数据失败: $e');
    }
  }

  // 启动交易数据收集
  Future<void> startTradeDataCollection(
      {Duration interval = const Duration(minutes: 10)}) async {
    if (_isCollectingTrades) return;

    _isCollectingTrades = true;
    print('开始收集交易数据，间隔: ${interval.inSeconds}秒');

    // 立即收集一次
    await collectTradeData();

    // 设置定时器
    _tradeCollectionTimer = Timer.periodic(interval, (_) async {
      await collectTradeData();
    });
  }

  // 停止交易数据收集
  void stopTradeDataCollection() {
    _tradeCollectionTimer?.cancel();
    _tradeCollectionTimer = null;
    _isCollectingTrades = false;
    print('已停止交易数据收集');
  }

  // 收集交易数据
  Future<void> collectTradeData() async {
    try {
      print('正在收集交易数据...');

      // 获取要收集的交易对列表（限制数量，避免请求过多）
      final symbols = (await _getSymbolsToCollect()).take(5).toList();

      for (final symbol in symbols) {
        try {
          // 获取最近的交易数据
          final trades = await _okxApi.getRecentTrades(symbol);

          // 转换为TradeData对象
          final tradeDataList = trades
              .map((trade) => TradeData(
                    tradeId: trade['tradeId'] ??
                        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}',
                    timestamp: DateTime.fromMillisecondsSinceEpoch(
                        int.parse(trade['timestamp'])),
                    symbol: symbol,
                    price: double.parse(trade['price']),
                    amount: double.parse(trade['size']),
                    direction: trade['side'],
                    exchange: 'OKX',
                    type: 'spot',
                    fee: 0.0, // 交易所API通常不提供手续费信息
                  ))
              .toList();

          // 保存到PostgreSQL
          await _postgresService.saveTradeDataBatch(tradeDataList);

          print('成功收集并保存了${tradeDataList.length}条$symbol的交易数据');

          // 添加延迟，避免请求过于频繁
          await Future.delayed(const Duration(seconds: 2));
        } catch (e) {
          print('收集$symbol交易数据失败: $e');
        }
      }
    } catch (e) {
      print('收集交易数据失败: $e');
    }
  }

  // 启动情绪数据收集
  Future<void> startSentimentDataCollection(
      {Duration interval = const Duration(hours: 6)}) async {
    if (_isCollectingSentiment) return;

    _isCollectingSentiment = true;
    print('开始收集情绪数据，间隔: ${interval.inMinutes}分钟');

    // 立即收集一次
    await collectSentimentData();

    // 设置定时器
    _sentimentCollectionTimer = Timer.periodic(interval, (_) async {
      await collectSentimentData();
    });
  }

  // 停止情绪数据收集
  void stopSentimentDataCollection() {
    _sentimentCollectionTimer?.cancel();
    _sentimentCollectionTimer = null;
    _isCollectingSentiment = false;
    print('已停止情绪数据收集');
  }

  // 收集情绪数据
  Future<void> collectSentimentData() async {
    try {
      print('正在收集情绪数据...');

      // 使用高级新闻服务搜索新闻
      final newsImpactAnalysis =
          await _advancedNewsService.getAllNewsImpactAnalysis();

      // 转换为SentimentData对象并保存
      for (final symbol in newsImpactAnalysis.keys) {
        final newsItems = newsImpactAnalysis[symbol]!;

        for (final item in newsItems) {
          final news = item['news'];
          final impactScore = item['impact_score'] as double;
          final sentiment = item['sentiment'] as String;

          // 创建情绪数据对象
          final sentimentData = SentimentData(
            timestamp: DateTime.parse(news.publishedAt),
            source: news.source,
            symbol: symbol,
            sentimentScore: impactScore,
            mentionCount: 1, // 每条新闻算作一次提及
            additionalData: {
              'sentiment': sentiment,
              'title': news.title,
              'url': news.url,
            },
          );

          // 保存到PostgreSQL
          await _postgresService.saveSentimentData(sentimentData);
        }
      }

      print('成功收集并保存了情绪数据');
    } catch (e) {
      print('收集情绪数据失败: $e');
    }
  }

  // 启动数据聚合
  void startDataAggregation({Duration interval = const Duration(hours: 24)}) {
    print('开始数据聚合，间隔: ${interval.inHours}小时');

    // 设置定时器
    _dataAggregationTimer = Timer.periodic(interval, (_) async {
      await aggregateHistoricalData();
    });
  }

  // 停止数据聚合
  void stopDataAggregation() {
    _dataAggregationTimer?.cancel();
    _dataAggregationTimer = null;
    print('已停止数据聚合');
  }

  // 聚合历史数据
  Future<void> aggregateHistoricalData() async {
    try {
      print('正在聚合历史数据...');

      // 这里可以实现数据聚合逻辑，例如：
      // 1. 从InfluxDB查询高精度数据
      // 2. 进行降采样和聚合
      // 3. 将聚合结果保存回InfluxDB

      print('成功聚合历史数据');
    } catch (e) {
      print('聚合历史数据失败: $e');
    }
  }

  // 获取要收集的交易对列表
  Future<List<String>> _getSymbolsToCollect() async {
    try {
      // 从环境变量获取配置的交易对
      final configuredSymbols = dotenv.env['COLLECT_SYMBOLS']?.split(',');
      if (configuredSymbols != null && configuredSymbols.isNotEmpty) {
        return configuredSymbols;
      }

      // 如果没有配置，则获取交易量最大的前20个交易对
      final instruments = await _okxApi.getAllInstruments();

      // 过滤出USDT交易对
      final usdtPairs = instruments
          .where((i) => i['instId'].toString().endsWith('-USDT'))
          .map((i) => i['instId'].toString())
          .take(20)
          .toList();

      return usdtPairs;
    } catch (e) {
      print('获取交易对列表失败: $e');
      // 返回默认交易对
      return ['BTC-USDT', 'ETH-USDT', 'SOL-USDT', 'XRP-USDT', 'DOGE-USDT'];
    }
  }
}
