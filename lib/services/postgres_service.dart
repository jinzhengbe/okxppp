import 'dart:async';
import 'package:postgres/postgres.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/trade_data.dart';
import '../models/sentiment_data.dart';

class PostgresService {
  static final PostgresService _instance = PostgresService._internal();
  late PostgreSQLConnection _connection;
  bool _isConnected = false;

  // 单例模式
  factory PostgresService() {
    return _instance;
  }

  PostgresService._internal() {
    _initConnection();
  }

  // 初始化连接
  void _initConnection() {
    final host = dotenv.env['POSTGRES_HOST'] ?? 'localhost';
    final port = int.parse(dotenv.env['POSTGRES_PORT'] ?? '5432');
    final database = dotenv.env['POSTGRES_DB'] ?? 'crypto_trading';
    final username = dotenv.env['POSTGRES_USER'] ?? 'admin';
    final password = dotenv.env['POSTGRES_PASSWORD'] ?? 'password';

    _connection = PostgreSQLConnection(
      host,
      port,
      database,
      username: username,
      password: password,
    );
  }

  // 连接到数据库
  Future<void> connect() async {
    if (!_isConnected) {
      try {
        await _connection.open();
        _isConnected = true;
        print('已连接到PostgreSQL数据库');

        // 确保表已创建
        await _createTables();
      } catch (e) {
        print('连接PostgreSQL数据库失败: $e');
        rethrow;
      }
    }
  }

  // 创建必要的表
  Future<void> _createTables() async {
    try {
      // 创建交易数据表
      await _connection.execute('''
        CREATE TABLE IF NOT EXISTS trades (
          id SERIAL PRIMARY KEY,
          trade_id TEXT NOT NULL,
          timestamp TIMESTAMP NOT NULL,
          symbol TEXT NOT NULL,
          price DOUBLE PRECISION NOT NULL,
          amount DOUBLE PRECISION NOT NULL,
          direction TEXT NOT NULL,
          exchange TEXT NOT NULL,
          type TEXT NOT NULL,
          fee DOUBLE PRECISION NOT NULL,
          created_at TIMESTAMP NOT NULL DEFAULT NOW()
        )
      ''');

      // 创建情绪数据表
      await _connection.execute('''
        CREATE TABLE IF NOT EXISTS sentiment (
          id SERIAL PRIMARY KEY,
          timestamp TIMESTAMP NOT NULL,
          source TEXT NOT NULL,
          symbol TEXT NOT NULL,
          sentiment_score DOUBLE PRECISION NOT NULL,
          mention_count INTEGER NOT NULL,
          additional_data TEXT,
          created_at TIMESTAMP NOT NULL DEFAULT NOW()
        )
      ''');

      // 创建索引
      await _connection.execute(
          'CREATE INDEX IF NOT EXISTS idx_trades_symbol ON trades (symbol)');
      await _connection.execute(
          'CREATE INDEX IF NOT EXISTS idx_trades_timestamp ON trades (timestamp)');
      await _connection.execute(
          'CREATE INDEX IF NOT EXISTS idx_sentiment_symbol ON sentiment (symbol)');
      await _connection.execute(
          'CREATE INDEX IF NOT EXISTS idx_sentiment_timestamp ON sentiment (timestamp)');

      print('数据库表已创建');
    } catch (e) {
      print('创建数据库表失败: $e');
      rethrow;
    }
  }

  // 保存交易数据
  Future<void> saveTradeData(TradeData tradeData) async {
    try {
      await connect();

      await _connection.execute('''
        INSERT INTO trades (
          trade_id, timestamp, symbol, price, amount, direction, exchange, type, fee, created_at
        ) VALUES (
          @tradeId, @timestamp, @symbol, @price, @amount, @direction, @exchange, @type, @fee, @createdAt
        )
      ''', substitutionValues: {
        'tradeId': tradeData.tradeId,
        'timestamp': tradeData.timestamp.toUtc(),
        'symbol': tradeData.symbol,
        'price': tradeData.price,
        'amount': tradeData.amount,
        'direction': tradeData.direction,
        'exchange': tradeData.exchange,
        'type': tradeData.type,
        'fee': tradeData.fee,
        'createdAt': DateTime.now().toUtc(),
      });
    } catch (e) {
      print('保存交易数据失败: $e');
      rethrow;
    }
  }

  // 批量保存交易数据
  Future<void> saveTradeDataBatch(List<TradeData> tradeDataList) async {
    try {
      await connect();

      await _connection.transaction((ctx) async {
        for (final tradeData in tradeDataList) {
          await ctx.execute('''
            INSERT INTO trades (
              trade_id, timestamp, symbol, price, amount, direction, exchange, type, fee, created_at
            ) VALUES (
              @tradeId, @timestamp, @symbol, @price, @amount, @direction, @exchange, @type, @fee, @createdAt
            )
          ''', substitutionValues: {
            'tradeId': tradeData.tradeId,
            'timestamp': tradeData.timestamp.toUtc(),
            'symbol': tradeData.symbol,
            'price': tradeData.price,
            'amount': tradeData.amount,
            'direction': tradeData.direction,
            'exchange': tradeData.exchange,
            'type': tradeData.type,
            'fee': tradeData.fee,
            'createdAt': DateTime.now().toUtc(),
          });
        }
      });
    } catch (e) {
      print('批量保存交易数据失败: $e');
      rethrow;
    }
  }

  // 保存情绪数据
  Future<void> saveSentimentData(SentimentData sentimentData) async {
    try {
      await connect();

      await _connection.execute('''
        INSERT INTO sentiment (
          timestamp, source, symbol, sentiment_score, mention_count, additional_data, created_at
        ) VALUES (
          @timestamp, @source, @symbol, @sentimentScore, @mentionCount, @additionalData, @createdAt
        )
      ''', substitutionValues: {
        'timestamp': sentimentData.timestamp.toUtc(),
        'source': sentimentData.source,
        'symbol': sentimentData.symbol,
        'sentimentScore': sentimentData.sentimentScore,
        'mentionCount': sentimentData.mentionCount,
        'additionalData': sentimentData.additionalData != null
            ? sentimentData.additionalData.toString()
            : null,
        'createdAt': DateTime.now().toUtc(),
      });
    } catch (e) {
      print('保存情绪数据失败: $e');
      rethrow;
    }
  }

  // 查询交易数据
  Future<List<TradeData>> queryTradeData({
    required String symbol,
    required DateTime start,
    required DateTime end,
    String? direction,
    String? exchange,
    int limit = 100,
  }) async {
    try {
      await connect();

      String query = '''
        SELECT * FROM trades
        WHERE symbol = @symbol
        AND timestamp BETWEEN @start AND @end
      ''';

      Map<String, dynamic> substitutionValues = {
        'symbol': symbol,
        'start': start.toUtc(),
        'end': end.toUtc(),
      };

      if (direction != null) {
        query += ' AND direction = @direction';
        substitutionValues['direction'] = direction;
      }

      if (exchange != null) {
        query += ' AND exchange = @exchange';
        substitutionValues['exchange'] = exchange;
      }

      query += ' ORDER BY timestamp DESC LIMIT @limit';
      substitutionValues['limit'] = limit;

      final results = await _connection.mappedResultsQuery(
        query,
        substitutionValues: substitutionValues,
      );

      return results.map((row) {
        final data = row['trades']!;
        return TradeData(
          tradeId: data['trade_id'] as String,
          timestamp: data['timestamp'] as DateTime,
          symbol: data['symbol'] as String,
          price: (data['price'] as num).toDouble(),
          amount: (data['amount'] as num).toDouble(),
          direction: data['direction'] as String,
          exchange: data['exchange'] as String,
          type: data['type'] as String,
          fee: (data['fee'] as num).toDouble(),
        );
      }).toList();
    } catch (e) {
      print('查询交易数据失败: $e');
      return [];
    }
  }

  // 查询情绪数据
  Future<List<SentimentData>> querySentimentData({
    required String symbol,
    required DateTime start,
    required DateTime end,
    String? source,
    int limit = 100,
  }) async {
    try {
      await connect();

      String query = '''
        SELECT * FROM sentiment
        WHERE symbol = @symbol
        AND timestamp BETWEEN @start AND @end
      ''';

      Map<String, dynamic> substitutionValues = {
        'symbol': symbol,
        'start': start.toUtc(),
        'end': end.toUtc(),
      };

      if (source != null) {
        query += ' AND source = @source';
        substitutionValues['source'] = source;
      }

      query += ' ORDER BY timestamp DESC LIMIT @limit';
      substitutionValues['limit'] = limit;

      final results = await _connection.mappedResultsQuery(
        query,
        substitutionValues: substitutionValues,
      );

      return results.map((row) {
        final data = row['sentiment']!;
        return SentimentData(
          timestamp: data['timestamp'] as DateTime,
          source: data['source'] as String,
          symbol: data['symbol'] as String,
          sentimentScore: (data['sentiment_score'] as num).toDouble(),
          mentionCount: data['mention_count'] as int,
          additionalData: data['additional_data'] != null
              ? _parseAdditionalData(data['additional_data'] as String)
              : null,
        );
      }).toList();
    } catch (e) {
      print('查询情绪数据失败: $e');
      return [];
    }
  }

  // 解析额外数据
  Map<String, dynamic>? _parseAdditionalData(String data) {
    try {
      // 简单的字符串到Map转换，实际应用中可能需要更复杂的解析
      final result = <String, dynamic>{};
      final pairs = data.replaceAll('{', '').replaceAll('}', '').split(',');

      for (final pair in pairs) {
        final keyValue = pair.split(':');
        if (keyValue.length == 2) {
          final key = keyValue[0].trim();
          final value = keyValue[1].trim();
          result[key] = value;
        }
      }

      return result;
    } catch (e) {
      print('解析额外数据失败: $e');
      return null;
    }
  }

  // 关闭连接
  Future<void> close() async {
    if (_isConnected) {
      await _connection.close();
      _isConnected = false;
      print('已关闭PostgreSQL连接');
    }
  }
}
