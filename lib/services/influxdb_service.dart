import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/price_data.dart';
import '../models/orderbook_data.dart';
import '../models/sentiment_data.dart';

class InfluxDBService {
  static final InfluxDBService _instance = InfluxDBService._internal();

  late String _url;
  late String _token;
  late String _org;
  late String _bucket;

  // 单例模式
  factory InfluxDBService() {
    return _instance;
  }

  InfluxDBService._internal() {
    _initConfig();
  }

  // 初始化配置
  void _initConfig() {
    _url = dotenv.env['INFLUXDB_URL'] ?? 'http://localhost:8086';
    _token = dotenv.env['INFLUXDB_TOKEN'] ?? 'my-super-secret-auth-token';
    _org = dotenv.env['INFLUXDB_ORG'] ?? 'crypto';
    _bucket = dotenv.env['INFLUXDB_BUCKET'] ?? 'crypto_data';
  }

  // 保存价格数据
  Future<void> savePriceData(PriceData priceData) async {
    try {
      final lineProtocol = _convertToLineProtocol(priceData.toInfluxPoint());
      await _writeData(lineProtocol);
    } catch (e) {
      print('保存价格数据到InfluxDB失败: $e');
      rethrow;
    }
  }

  // 批量保存价格数据
  Future<void> savePriceDataBatch(List<PriceData> priceDataList) async {
    try {
      final lineProtocols = priceDataList
          .map((data) => _convertToLineProtocol(data.toInfluxPoint()))
          .join('\n');
      await _writeData(lineProtocols);
    } catch (e) {
      print('批量保存价格数据到InfluxDB失败: $e');
      rethrow;
    }
  }

  // 保存订单簿数据
  Future<void> saveOrderBookData(OrderBookData orderBookData) async {
    try {
      final lineProtocol =
          _convertToLineProtocol(orderBookData.toInfluxPoint());
      await _writeData(lineProtocol);
    } catch (e) {
      print('保存订单簿数据到InfluxDB失败: $e');
      rethrow;
    }
  }

  // 保存情绪数据
  Future<void> saveSentimentData(SentimentData sentimentData) async {
    try {
      final lineProtocol =
          _convertToLineProtocol(sentimentData.toInfluxPoint());
      await _writeData(lineProtocol);
    } catch (e) {
      print('保存情绪数据到InfluxDB失败: $e');
      rethrow;
    }
  }

  // 将Map转换为InfluxDB行协议格式
  String _convertToLineProtocol(Map<String, dynamic> data) {
    final measurement = data['measurement'] as String;
    final tags = data['tags'] as Map<String, dynamic>;
    final fields = data['fields'] as Map<String, dynamic>;
    final time = data['time'] as int?;

    // 构建标签字符串
    String tagsStr =
        tags.entries.map((entry) => '${entry.key}=${entry.value}').join(',');

    // 构建字段字符串
    String fieldsStr = fields.entries.map((entry) {
      var value = entry.value;
      if (value is String) {
        // 字符串需要用双引号括起来，并转义双引号
        return '${entry.key}="${value.replaceAll('"', '\\"')}"';
      } else if (value is bool) {
        // 布尔值转为t或f
        return '${entry.key}=${value ? 't' : 'f'}';
      } else {
        // 数字直接使用
        return '${entry.key}=${value}';
      }
    }).join(',');

    // 构建完整的行协议
    String lineProtocol = '$measurement,$tagsStr $fieldsStr';

    // 添加时间戳（如果有）
    if (time != null) {
      lineProtocol += ' $time';
    }

    return lineProtocol;
  }

  // 写入数据到InfluxDB
  Future<void> _writeData(String lineProtocol) async {
    final uri =
        Uri.parse('$_url/api/v2/write?org=$_org&bucket=$_bucket&precision=ns');

    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Token $_token',
        'Content-Type': 'text/plain; charset=utf-8',
      },
      body: lineProtocol,
    );

    if (response.statusCode != 204) {
      throw Exception('InfluxDB写入失败: ${response.statusCode} ${response.body}');
    }
  }

  // 查询价格数据
  Future<List<PriceData>> queryPriceData({
    required String symbol,
    required DateTime start,
    required DateTime end,
    String? exchange,
    String aggregateWindow = '1h',
  }) async {
    try {
      final query = '''
        from(bucket: "$_bucket")
          |> range(start: ${start.toUtc().toIso8601String()}, stop: ${end.toUtc().toIso8601String()})
          |> filter(fn: (r) => r._measurement == "price_data")
          |> filter(fn: (r) => r.symbol == "$symbol")
          ${exchange != null ? '|> filter(fn: (r) => r.exchange == "$exchange")' : ''}
          |> aggregateWindow(every: $aggregateWindow, fn: mean)
          |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
      ''';

      final result = await _queryData(query);

      List<PriceData> priceDataList = [];

      for (final record in result) {
        try {
          final timestamp = DateTime.parse(record['_time'] as String);
          final symbol = record['symbol'] as String;
          final exchange = record['exchange'] as String;
          final open = (record['open'] as num?)?.toDouble() ?? 0.0;
          final high = (record['high'] as num?)?.toDouble() ?? 0.0;
          final low = (record['low'] as num?)?.toDouble() ?? 0.0;
          final close = (record['close'] as num?)?.toDouble() ?? 0.0;
          final volume = (record['volume'] as num?)?.toDouble() ?? 0.0;
          final quoteVolume =
              (record['quoteVolume'] as num?)?.toDouble() ?? 0.0;

          priceDataList.add(PriceData(
            timestamp: timestamp,
            symbol: symbol,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            quoteVolume: quoteVolume,
            exchange: exchange,
          ));
        } catch (e) {
          print('解析价格数据记录失败: $e');
          // 继续处理下一条记录
        }
      }

      return priceDataList;
    } catch (e) {
      print('查询价格数据失败: $e');
      return [];
    }
  }

  // 查询数据
  Future<List<Map<String, dynamic>>> _queryData(String fluxQuery) async {
    final uri = Uri.parse('$_url/api/v2/query?org=$_org');

    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Token $_token',
        'Content-Type': 'application/json',
        'Accept': 'application/csv',
      },
      body: jsonEncode({
        'query': fluxQuery,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('InfluxDB查询失败: ${response.statusCode} ${response.body}');
    }

    // 解析CSV响应
    return _parseCSV(response.body);
  }

  // 解析CSV响应
  List<Map<String, dynamic>> _parseCSV(String csv) {
    final lines = csv.split('\n');
    if (lines.length < 2) {
      return [];
    }

    // 第一行是注释，第二行是列名
    final headers = lines[1].split(',');

    List<Map<String, dynamic>> result = [];

    // 从第三行开始是数据
    for (int i = 2; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      final values = line.split(',');
      if (values.length != headers.length) {
        continue;
      }

      Map<String, dynamic> record = {};
      for (int j = 0; j < headers.length; j++) {
        record[headers[j]] = values[j];
      }

      result.add(record);
    }

    return result;
  }
}
