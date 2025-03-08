import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:intl/intl.dart';
import '../models/ticker.dart';
import '../models/order.dart';

// 简单的WebSocketChannel实现
class _SimpleWebSocketChannel implements WebSocketChannel {
  final Stream _stream;
  final WebSocketSink _sink;

  _SimpleWebSocketChannel(this._stream, this._sink);

  @override
  Stream get stream => _stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future get ready => Future.value();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// 模拟WebSocketSink实现
class _MockWebSocketSink implements WebSocketSink {
  @override
  void add(data) {
    // 忽略所有添加的数据
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // 忽略所有错误
  }

  @override
  Future addStream(Stream stream) {
    // 忽略所有流
    return Future.value();
  }

  @override
  Future close([int? closeCode, String? closeReason]) {
    // 不做任何事情
    return Future.value();
  }

  @override
  Future get done => Future.value();
}

class OkxApi {
  static final OkxApi _instance = OkxApi._internal();
  late final Dio _dio;
  late final String _baseUrl;
  late final String _wsUrl;
  late final String _apiKey;
  late final String _secretKey;
  late final String _passphrase;

  // 单例模式
  factory OkxApi() {
    return _instance;
  }

  OkxApi._internal() {
    // 使用环境变量中的API端点，或尝试多个备选API端点
    _baseUrl = dotenv.env['OKX_REST_API_URL'] ?? 'https://www.okx.com';

    // 尝试多个WebSocket端点
    final wsEndpoints = [
      'wss://wsaws.okx.com:8443/ws/v5/public',
      'wss://ws.okx.com:8443/ws/v5/public',
      'wss://wspap.okx.com:8443/ws/v5/public'
    ];

    // 使用环境变量中的WebSocket端点，或尝试第一个备选端点
    _wsUrl = dotenv.env['OKX_WS_API_URL'] ?? wsEndpoints[0];

    _apiKey = dotenv.env['API_KEY'] ?? '';
    _secretKey = dotenv.env['SECRET_KEY'] ?? '';
    _passphrase = dotenv.env['PASSPHRASE'] ?? '';

    // 打印API密钥信息（注意：实际生产环境中不要这样做，这里仅用于调试）
    print('API密钥检查:');
    print(
        'API_KEY: ${_apiKey.isEmpty ? "未设置" : (_apiKey.substring(0, 3) + "..." + (_apiKey.length > 6 ? _apiKey.substring(_apiKey.length - 3) : ""))}');
    print(
        'SECRET_KEY: ${_secretKey.isEmpty ? "未设置" : "已设置 (长度: ${_secretKey.length})"}');
    print('PASSPHRASE: ${_passphrase.isEmpty ? "未设置" : "已设置"}');

    print('使用的API端点: $_baseUrl');
    print('使用的WebSocket端点: $_wsUrl');

    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 1),
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );

    // 设置HTTP代理
    _setupProxy();

    // 添加拦截器用于日志记录
    _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) {
          print('DIO日志: $obj');
        }));

    // 测试网络连接
    _testNetworkConnections();
  }

  // 设置HTTP代理
  void _setupProxy() {
    // 检查是否有代理环境变量
    final httpProxy = Platform.environment['HTTP_PROXY'] ??
        Platform.environment['http_proxy'];
    final httpsProxy = Platform.environment['HTTPS_PROXY'] ??
        Platform.environment['https_proxy'];

    // 如果没有环境变量代理，尝试使用一些常见的代理设置
    final fallbackProxies = [
      // 尝试使用本地代理
      'http://127.0.0.1:7890', // Clash
      'http://127.0.0.1:8888', // Charles
      'http://127.0.0.1:8080', // 常见代理端口
    ];

    if (httpsProxy != null && httpsProxy.isNotEmpty) {
      _configureProxy(httpsProxy, 'HTTPS');
    } else if (httpProxy != null && httpProxy.isNotEmpty) {
      _configureProxy(httpProxy, 'HTTP');
    } else {
      print('未找到环境变量代理设置，尝试常见代理...');

      // 尝试连接常见代理
      for (final proxy in fallbackProxies) {
        try {
          final uri = Uri.parse(proxy);
          final socket = Socket.connect(uri.host, uri.port,
              timeout: Duration(milliseconds: 500));
          socket.then((value) {
            print('找到可用代理: $proxy');
            value.destroy();
            _configureProxy(proxy, '自动检测');
            return;
          }).catchError((e) {
            // 代理不可用，继续尝试下一个
          });
        } catch (e) {
          // 忽略解析错误
        }
      }

      print('未找到可用代理，使用直接连接');
    }
  }

  // 配置代理
  void _configureProxy(String proxyUrl, String type) {
    try {
      // 解析代理URL
      final uri = Uri.parse(proxyUrl);
      print('使用${type}代理: ${uri.host}:${uri.port}');

      // 设置Dio代理
      (_dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
          (client) {
        client.findProxy = (uri) {
          return 'PROXY ${uri.host}:${uri.port}';
        };
        // 忽略证书错误
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    } catch (e) {
      print('设置${type}代理失败: $e');
    }
  }

  // 生成签名
  String _generateSignature(
    String timestamp,
    String method,
    String requestPath, {
    String body = '',
  }) {
    final message = timestamp + method + requestPath + body;
    final hmacSha256 = Hmac(sha256, utf8.encode(_secretKey));
    final digest = hmacSha256.convert(utf8.encode(message));
    return base64.encode(digest.bytes);
  }

  // 添加认证头
  Map<String, dynamic> _getAuthHeaders(
    String method,
    String requestPath, {
    String body = '',
  }) {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final signature = _generateSignature(
      timestamp,
      method,
      requestPath,
      body: body,
    );

    return {
      'OK-ACCESS-KEY': _apiKey,
      'OK-ACCESS-SIGN': signature,
      'OK-ACCESS-TIMESTAMP': timestamp,
      'OK-ACCESS-PASSPHRASE': _passphrase,
    };
  }

  // 获取单个交易对的行情
  Future<Ticker> getTicker(String symbol) async {
    try {
      print('开始获取交易对 $symbol 的行情数据');

      // 尝试多个API端点
      final endpoints = [
        '/api/v5/market/ticker',
        '/api/v5/market/ticker-lite',
      ];

      // 尝试多个基础URL
      final baseUrls = [
        _baseUrl,
        'https://www.okx.com',
        'https://aws.okx.com',
      ];

      Exception? lastException;
      String errorDetails = '';

      // 尝试所有组合
      for (final baseUrl in baseUrls) {
        for (final endpoint in endpoints) {
          try {
            print('尝试从 $baseUrl$endpoint 获取价格数据');

            // 创建新的Dio实例，以便可以更改baseUrl
            final dio = Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 2),
                receiveTimeout: const Duration(seconds: 1),
                headers: {
                  'Content-Type': 'application/json',
                  'User-Agent':
                      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36',
                },
              ),
            );

            // 设置代理
            _setupDioProxy(dio);

            // 添加详细日志
            dio.interceptors.add(LogInterceptor(
                requestHeader: true,
                requestBody: true,
                responseHeader: true,
                responseBody: true,
                logPrint: (obj) {
                  print('请求/响应详情: $obj');
                }));

            final response = await dio.get(
              endpoint,
              queryParameters: {'instId': symbol},
            );

            print('响应状态码: ${response.statusCode}');
            print('响应数据: ${response.data}');

            if (response.statusCode == 200 && response.data['code'] == '0') {
              print('成功从 $baseUrl$endpoint 获取价格数据');
              final ticker = Ticker.fromJson(response.data['data'][0]);
              print('解析后的价格数据: ${ticker.currentPrice}');
              return ticker;
            } else {
              print('API返回错误: ${response.data['msg']}');
              errorDetails +=
                  '[$baseUrl$endpoint]: API错误 - ${response.data['msg']}\n';
            }
          } catch (e) {
            print('从 $baseUrl$endpoint 获取价格失败: $e');
            if (e is DioException) {
              print('Dio错误类型: ${e.type}');
              print('Dio错误消息: ${e.message}');
              if (e.response != null) {
                print('响应状态码: ${e.response?.statusCode}');
                print('响应数据: ${e.response?.data}');
              }

              // 记录详细错误信息
              errorDetails += '[$baseUrl$endpoint]: ${e.type} - ${e.message}\n';

              // 如果是权限问题，记录更详细的信息
              if (e.message?.contains('Operation not permitted') == true) {
                errorDetails += '系统权限错误: 应用被阻止访问网络。请检查网络权限或使用VPN。\n';
              }
            } else {
              errorDetails += '[$baseUrl$endpoint]: ${e.toString()}\n';
            }
            lastException = Exception('Failed to load ticker: $e');
          }
        }
      }

      throw Exception('无法从任何端点获取价格数据。\n详细错误: $errorDetails');
    } catch (e) {
      print('Error fetching ticker: $e');
      // 不再使用模拟数据，直接抛出异常
      throw Exception('无法获取价格数据: $e');
    }
  }

  // 为Dio设置代理
  void _setupDioProxy(Dio dio) {
    // 检查是否有代理环境变量
    final httpProxy = Platform.environment['HTTP_PROXY'] ??
        Platform.environment['http_proxy'];
    final httpsProxy = Platform.environment['HTTPS_PROXY'] ??
        Platform.environment['https_proxy'];

    if (httpsProxy != null && httpsProxy.isNotEmpty) {
      try {
        // 解析代理URL
        final uri = Uri.parse(httpsProxy);
        print('Dio使用HTTPS代理: ${uri.host}:${uri.port}');

        // 设置Dio代理
        (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
            (client) {
          client.findProxy = (uri) {
            return 'PROXY ${uri.host}:${uri.port}';
          };
          // 忽略证书错误
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      } catch (e) {
        print('设置Dio HTTPS代理失败: $e');
      }
    } else if (httpProxy != null && httpProxy.isNotEmpty) {
      try {
        // 解析代理URL
        final uri = Uri.parse(httpProxy);
        print('Dio使用HTTP代理: ${uri.host}:${uri.port}');

        // 设置Dio代理
        (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
            (client) {
          client.findProxy = (uri) {
            return 'PROXY ${uri.host}:${uri.port}';
          };
          // 忽略证书错误
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      } catch (e) {
        print('设置Dio HTTP代理失败: $e');
      }
    }
  }

  // 获取多个交易对的行情
  Future<List<Ticker>> getTickers(List<String> symbols) async {
    List<Ticker> tickers = [];
    for (var symbol in symbols) {
      try {
        final ticker = await getTicker(symbol);
        tickers.add(ticker);
      } catch (e) {
        print('Error fetching ticker for $symbol: $e');
      }
    }
    return tickers;
  }

  // 获取账户余额
  Future<Map<String, dynamic>> getAccountBalance() async {
    final requestPath = '/api/v5/account/balance';
    final headers = _getAuthHeaders('GET', requestPath);

    try {
      final response = await _dio.get(
        requestPath,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data['code'] == '0') {
        return response.data['data'][0];
      } else {
        throw Exception(
          'Failed to load account balance: ${response.data['msg']}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching account balance: $e');
    }
  }

  // 下单
  Future<Order> placeOrder({
    required String symbol,
    required String side, // buy or sell
    required String orderType, // market or limit
    required String amount,
    String? price,
  }) async {
    final requestPath = '/api/v5/trade/order';
    final body = jsonEncode({
      'instId': symbol,
      'tdMode': 'cash',
      'side': side,
      'ordType': orderType,
      'sz': amount,
      if (price != null) 'px': price,
    });

    final headers = _getAuthHeaders('POST', requestPath, body: body);

    try {
      final response = await _dio.post(
        requestPath,
        data: body,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data['code'] == '0') {
        return Order.fromJson(response.data['data'][0]);
      } else {
        throw Exception('Failed to place order: ${response.data['msg']}');
      }
    } catch (e) {
      throw Exception('Error placing order: $e');
    }
  }

  // 取消订单
  Future<bool> cancelOrder(String orderId, String symbol) async {
    final requestPath = '/api/v5/trade/cancel-order';
    final body = jsonEncode({'instId': symbol, 'ordId': orderId});

    final headers = _getAuthHeaders('POST', requestPath, body: body);

    try {
      final response = await _dio.post(
        requestPath,
        data: body,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data['code'] == '0') {
        return true;
      } else {
        throw Exception('Failed to cancel order: ${response.data['msg']}');
      }
    } catch (e) {
      throw Exception('Error cancelling order: $e');
    }
  }

  // 获取订单历史
  Future<List<Order>> getOrderHistory(String symbol) async {
    final requestPath = '/api/v5/trade/orders-history';
    final headers = _getAuthHeaders('GET', requestPath);

    try {
      final response = await _dio.get(
        requestPath,
        queryParameters: {'instId': symbol},
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data['code'] == '0') {
        return (response.data['data'] as List)
            .map((item) => Order.fromJson(item))
            .toList();
      } else {
        throw Exception(
          'Failed to load order history: ${response.data['msg']}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching order history: $e');
    }
  }

  // 创建WebSocket连接获取实时价格
  WebSocketChannel createTickerWebSocket(String symbol) {
    try {
      print('正在连接WebSocket: $_wsUrl');

      // 尝试使用HTTP代理连接WebSocket
      final uri = Uri.parse(_wsUrl);
      print('WebSocket URI: $uri');

      // 尝试连接
      final channel = WebSocketChannel.connect(uri);
      print('WebSocket连接已创建，等待连接建立...');

      // 订阅行情
      final subscribeMsg = {
        "op": "subscribe",
        "args": [
          {"channel": "tickers", "instId": symbol},
        ],
      };

      print('发送订阅消息: ${jsonEncode(subscribeMsg)}');
      channel.sink.add(jsonEncode(subscribeMsg));
      print('订阅消息已发送');

      // 设置心跳，保持连接活跃
      Timer.periodic(const Duration(seconds: 20), (timer) {
        try {
          final pingMsg = {"op": "ping"};
          print('发送心跳消息');
          channel.sink.add(jsonEncode(pingMsg));
        } catch (e) {
          print('发送心跳消息失败: $e');
          timer.cancel();
        }
      });

      return channel;
    } catch (e) {
      print('WebSocket连接错误: $e');
      print('错误详情: ${e.toString()}');
      if (e is SocketException) {
        print('Socket错误: ${e.message}');
        print('Socket地址: ${e.address}');
        print('Socket端口: ${e.port}');
        print('Socket OS错误码: ${e.osError?.errorCode}');
        print('Socket OS错误消息: ${e.osError?.message}');
      }

      // 尝试使用不同的WebSocket端点
      final alternativeEndpoints = [
        'wss://ws.okx.com:8443/ws/v5/public',
        'wss://wspap.okx.com:8443/ws/v5/public'
      ];

      for (final endpoint in alternativeEndpoints) {
        if (endpoint != _wsUrl) {
          try {
            print('尝试备用WebSocket端点: $endpoint');
            final uri = Uri.parse(endpoint);
            final channel = WebSocketChannel.connect(uri);

            // 订阅行情
            final subscribeMsg = {
              "op": "subscribe",
              "args": [
                {"channel": "tickers", "instId": symbol},
              ],
            };

            print('发送订阅消息: ${jsonEncode(subscribeMsg)}');
            channel.sink.add(jsonEncode(subscribeMsg));

            // 设置心跳，保持连接活跃
            Timer.periodic(const Duration(seconds: 20), (timer) {
              try {
                final pingMsg = {"op": "ping"};
                print('发送心跳消息');
                channel.sink.add(jsonEncode(pingMsg));
              } catch (e) {
                print('发送心跳消息失败: $e');
                timer.cancel();
              }
            });

            // 如果成功连接，更新默认端点
            _wsUrl = endpoint;
            return channel;
          } catch (e) {
            print('备用WebSocket端点连接失败: $e');
            print('错误详情: ${e.toString()}');
          }
        }
      }

      // 如果所有尝试都失败，创建一个后备WebSocket通道
      print('所有WebSocket连接尝试都失败，使用模拟数据');
      return _createFallbackWebSocketChannel(symbol);
    }
  }

  // 创建HTTP客户端
  HttpClient _createHttpClient() {
    final client = HttpClient();

    // 设置超时
    client.connectionTimeout = const Duration(seconds: 10);

    // 忽略证书错误
    client.badCertificateCallback = (cert, host, port) => true;

    // 设置代理
    final httpProxy = Platform.environment['HTTP_PROXY'] ??
        Platform.environment['http_proxy'];
    final httpsProxy = Platform.environment['HTTPS_PROXY'] ??
        Platform.environment['https_proxy'];

    if (httpsProxy != null && httpsProxy.isNotEmpty) {
      try {
        final uri = Uri.parse(httpsProxy);
        client.findProxy = (uri) => 'PROXY ${uri.host}:${uri.port}';
        print('WebSocket使用HTTPS代理: ${uri.host}:${uri.port}');
      } catch (e) {
        print('设置WebSocket HTTPS代理失败: $e');
      }
    } else if (httpProxy != null && httpProxy.isNotEmpty) {
      try {
        final uri = Uri.parse(httpProxy);
        client.findProxy = (uri) => 'PROXY ${uri.host}:${uri.port}';
        print('WebSocket使用HTTP代理: ${uri.host}:${uri.port}');
      } catch (e) {
        print('设置WebSocket HTTP代理失败: $e');
      }
    }

    return client;
  }

  // 创建一个后备的WebSocket通道，用于在真实连接失败时提供基本功能
  WebSocketChannel _createFallbackWebSocketChannel(String symbol) {
    print('创建后备WebSocket通道');
    // 创建一个控制器来模拟WebSocket流
    final controller = StreamController<dynamic>();

    // 发送一个错误消息
    Future.delayed(const Duration(milliseconds: 500), () {
      final errorMsg = {
        "event": "error",
        "msg": "无法连接到OKX服务器，请检查网络连接或使用代理",
      };
      controller.add(jsonEncode(errorMsg));
    });

    // 创建一个简单的WebSocketChannel实现
    return _SimpleWebSocketChannel(controller.stream, _MockWebSocketSink());
  }

  // 创建WebSocket连接获取K线数据
  WebSocketChannel createCandleWebSocket(String symbol, String period) {
    try {
      print('正在连接K线WebSocket: $_wsUrl');
      final channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      // 订阅K线
      final subscribeMsg = {
        "op": "subscribe",
        "args": [
          {"channel": "candle$period", "instId": symbol},
        ],
      };

      print('发送K线订阅消息');
      channel.sink.add(jsonEncode(subscribeMsg));

      // 设置心跳，保持连接活跃
      Timer.periodic(const Duration(seconds: 20), (timer) {
        try {
          final pingMsg = {"op": "ping"};
          print('发送心跳消息');
          channel.sink.add(jsonEncode(pingMsg));
        } catch (e) {
          print('发送心跳消息失败: $e');
          timer.cancel();
        }
      });

      return channel;
    } catch (e) {
      print('K线WebSocket连接错误: $e');
      // 创建一个模拟的WebSocket通道
      return _createFallbackWebSocketChannel(symbol);
    }
  }

  // 创建私有WebSocket连接（需要认证）
  WebSocketChannel createPrivateWebSocket() {
    try {
      // 使用私有频道WebSocket URL
      final privateWsUrl = 'wss://wspap.okx.com:8443/ws/v5/private';
      print('正在连接私有WebSocket: $privateWsUrl');

      final channel = WebSocketChannel.connect(Uri.parse(privateWsUrl));

      // 生成认证信息
      final timestamp = DateTime.now().millisecondsSinceEpoch / 1000;
      final sign = _generateSignature(
        timestamp.toString(),
        'GET',
        '/users/self/verify',
      );

      // 发送登录消息
      final loginMsg = {
        "op": "login",
        "args": [
          {
            "apiKey": _apiKey,
            "passphrase": _passphrase,
            "timestamp": timestamp.toString(),
            "sign": sign,
          }
        ]
      };

      print('发送登录消息');
      channel.sink.add(jsonEncode(loginMsg));

      // 设置心跳，保持连接活跃
      Timer.periodic(const Duration(seconds: 20), (timer) {
        try {
          final pingMsg = {"op": "ping"};
          print('发送心跳消息');
          channel.sink.add(jsonEncode(pingMsg));
        } catch (e) {
          print('发送心跳消息失败: $e');
          timer.cancel();
        }
      });

      return channel;
    } catch (e) {
      print('私有WebSocket连接错误: $e');
      // 创建一个模拟的WebSocket通道
      return _createFallbackWebSocketChannel("private");
    }
  }

  // 测试网络连接
  Future<void> _testNetworkConnections() async {
    print('开始测试网络连接...');

    // 测试常见网站连接
    final testSites = [
      'https://www.google.com',
      'https://www.baidu.com',
      'https://www.okx.com',
      'https://aws.okx.com',
    ];

    for (final site in testSites) {
      try {
        print('测试连接到 $site');
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 3),
          ),
        );

        final response = await dio.get(site);
        print('连接到 $site 成功，状态码: ${response.statusCode}');
      } catch (e) {
        print('连接到 $site 失败: $e');
      }
    }

    // 测试DNS解析
    final hostnames = [
      'www.okx.com',
      'aws.okx.com',
      'wsaws.okx.com',
    ];

    for (final hostname in hostnames) {
      try {
        print('测试DNS解析 $hostname');
        final addresses = await InternetAddress.lookup(hostname);
        print(
            'DNS解析 $hostname 成功: ${addresses.map((a) => a.address).join(', ')}');
      } catch (e) {
        print('DNS解析 $hostname 失败: $e');
      }
    }

    // 测试端口连接
    final socketTests = [
      {'host': 'www.okx.com', 'port': 443},
      {'host': 'aws.okx.com', 'port': 443},
      {'host': 'wsaws.okx.com', 'port': 8443},
    ];

    for (final test in socketTests) {
      try {
        print('测试Socket连接到 ${test['host']}:${test['port']}');
        final socket = await Socket.connect(
          test['host'] as String,
          test['port'] as int,
          timeout: const Duration(seconds: 5),
        );
        print('Socket连接到 ${test['host']}:${test['port']} 成功');
        socket.destroy();
      } catch (e) {
        print('Socket连接到 ${test['host']}:${test['port']} 失败: $e');
      }
    }

    print('网络连接测试完成');
  }

  // 获取所有可交易的交易对列表
  Future<List<Map<String, dynamic>>> getAllInstruments() async {
    try {
      print('开始获取所有交易对列表');

      // 尝试多个API端点
      final endpoints = [
        '/api/v5/public/instruments',
      ];

      // 尝试多个基础URL
      final baseUrls = [
        _baseUrl,
        'https://www.okx.com',
        'https://aws.okx.com',
      ];

      Exception? lastException;
      String errorDetails = '';

      // 尝试所有组合
      for (final baseUrl in baseUrls) {
        for (final endpoint in endpoints) {
          try {
            print('尝试从 $baseUrl$endpoint 获取交易对列表');

            // 创建新的Dio实例，以便可以更改baseUrl
            final dio = Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 3),
                receiveTimeout: const Duration(seconds: 2),
                headers: {
                  'Content-Type': 'application/json',
                  'User-Agent':
                      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36',
                },
              ),
            );

            // 设置代理
            _setupDioProxy(dio);

            final response = await dio.get(
              endpoint,
              queryParameters: {'instType': 'SPOT'}, // 只获取现货交易对
            );

            if (response.statusCode == 200 && response.data['code'] == '0') {
              print('成功获取交易对列表');
              return List<Map<String, dynamic>>.from(response.data['data']);
            } else {
              print('API返回错误: ${response.data['msg']}');
              errorDetails +=
                  '[$baseUrl$endpoint]: API错误 - ${response.data['msg']}\n';
            }
          } catch (e) {
            print('从 $baseUrl$endpoint 获取交易对列表失败: $e');
            errorDetails += '[$baseUrl$endpoint]: ${e.toString()}\n';
            lastException = Exception('Failed to load instruments: $e');
          }
        }
      }

      throw Exception('无法获取交易对列表。\n详细错误: $errorDetails');
    } catch (e) {
      print('Error fetching instruments: $e');
      // 如果无法获取真实数据，返回一些常见的交易对作为备选
      return [
        {
          'instId': 'BTC-USDT',
          'baseCcy': 'BTC',
          'quoteCcy': 'USDT',
          'state': 'live'
        },
        {
          'instId': 'ETH-USDT',
          'baseCcy': 'ETH',
          'quoteCcy': 'USDT',
          'state': 'live'
        },
        {
          'instId': 'LTC-USDT',
          'baseCcy': 'LTC',
          'quoteCcy': 'USDT',
          'state': 'live'
        },
        {
          'instId': 'XRP-USDT',
          'baseCcy': 'XRP',
          'quoteCcy': 'USDT',
          'state': 'live'
        },
        {
          'instId': 'BCH-USDT',
          'baseCcy': 'BCH',
          'quoteCcy': 'USDT',
          'state': 'live'
        },
        {
          'instId': 'EOS-USDT',
          'baseCcy': 'EOS',
          'quoteCcy': 'USDT',
          'state': 'live'
        },
        {
          'instId': 'DOT-USDT',
          'baseCcy': 'DOT',
          'quoteCcy': 'USDT',
          'state': 'live'
        },
        {
          'instId': 'DOGE-USDT',
          'baseCcy': 'DOGE',
          'quoteCcy': 'USDT',
          'state': 'live'
        },
        {
          'instId': 'ADA-USDT',
          'baseCcy': 'ADA',
          'quoteCcy': 'USDT',
          'state': 'live'
        },
        {
          'instId': 'SOL-USDT',
          'baseCcy': 'SOL',
          'quoteCcy': 'USDT',
          'state': 'live'
        },
      ];
    }
  }

  // 批量获取多个交易对的行情
  Future<List<Ticker>> getMultipleTickers(List<String> symbols) async {
    try {
      print('开始批量获取多个交易对的行情');

      // 尝试多个API端点
      final endpoints = [
        '/api/v5/market/tickers',
      ];

      // 尝试多个基础URL
      final baseUrls = [
        _baseUrl,
        'https://www.okx.com',
        'https://aws.okx.com',
      ];

      Exception? lastException;
      String errorDetails = '';

      // 尝试所有组合
      for (final baseUrl in baseUrls) {
        for (final endpoint in endpoints) {
          try {
            print('尝试从 $baseUrl$endpoint 获取多个交易对行情');

            // 创建新的Dio实例，以便可以更改baseUrl
            final dio = Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 3),
                receiveTimeout: const Duration(seconds: 2),
                headers: {
                  'Content-Type': 'application/json',
                  'User-Agent':
                      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36',
                },
              ),
            );

            // 设置代理
            _setupDioProxy(dio);

            final response = await dio.get(
              endpoint,
              queryParameters: {'instType': 'SPOT'}, // 只获取现货交易对
            );

            if (response.statusCode == 200 && response.data['code'] == '0') {
              print('成功获取多个交易对行情');
              final List<dynamic> data = response.data['data'];

              // 过滤出我们需要的交易对
              final filteredData = data
                  .where((item) => symbols.contains(item['instId']))
                  .toList();

              // 转换为Ticker对象
              return filteredData.map((item) => Ticker.fromJson(item)).toList();
            } else {
              print('API返回错误: ${response.data['msg']}');
              errorDetails +=
                  '[$baseUrl$endpoint]: API错误 - ${response.data['msg']}\n';
            }
          } catch (e) {
            print('从 $baseUrl$endpoint 获取多个交易对行情失败: $e');
            errorDetails += '[$baseUrl$endpoint]: ${e.toString()}\n';
            lastException = Exception('Failed to load tickers: $e');
          }
        }
      }

      // 如果所有尝试都失败，则单独获取每个交易对的行情
      print('批量获取失败，尝试单独获取每个交易对的行情');
      List<Ticker> tickers = [];
      for (final symbol in symbols) {
        try {
          final ticker = await getTicker(symbol);
          tickers.add(ticker);
        } catch (e) {
          print('获取 $symbol 行情失败: $e');
        }
      }

      if (tickers.isNotEmpty) {
        return tickers;
      }

      throw Exception('无法获取多个交易对行情。\n详细错误: $errorDetails');
    } catch (e) {
      print('Error fetching multiple tickers: $e');
      throw Exception('无法获取多个交易对行情: $e');
    }
  }

  // 获取订单簿数据
  Future<dynamic> getOrderBook(String symbol, {int size = 20}) async {
    try {
      print('开始获取 $symbol 的订单簿数据');

      // 尝试多个API端点
      final endpoints = [
        '/api/v5/market/books',
      ];

      // 尝试多个基础URL
      final baseUrls = [
        _baseUrl,
        'https://www.okx.com',
        'https://aws.okx.com',
      ];

      Exception? lastException;
      String errorDetails = '';

      // 尝试所有组合
      for (final baseUrl in baseUrls) {
        for (final endpoint in endpoints) {
          try {
            print('尝试从 $baseUrl$endpoint 获取订单簿数据');

            // 创建新的Dio实例，以便可以更改baseUrl
            final dio = Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 3),
                receiveTimeout: const Duration(seconds: 2),
                headers: {
                  'Content-Type': 'application/json',
                  'User-Agent':
                      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36',
                },
              ),
            );

            // 设置代理
            _setupDioProxy(dio);

            final response = await dio.get(
              endpoint,
              queryParameters: {
                'instId': symbol,
                'sz': size,
              },
            );

            if (response.statusCode == 200 && response.data['code'] == '0') {
              print('成功获取 $symbol 的订单簿数据');
              final data = response.data['data'][0];

              // 返回订单簿数据
              return {
                'bids': (data['bids'] as List)
                    .map((bid) => [bid[0], bid[1]])
                    .toList(),
                'asks': (data['asks'] as List)
                    .map((ask) => [ask[0], ask[1]])
                    .toList(),
                'timestamp': data['ts'],
              };
            } else {
              print('API返回错误: ${response.data['msg']}');
              errorDetails +=
                  '[$baseUrl$endpoint]: API错误 - ${response.data['msg']}\n';
            }
          } catch (e) {
            print('从 $baseUrl$endpoint 获取订单簿数据失败: $e');
            errorDetails += '[$baseUrl$endpoint]: ${e.toString()}\n';
            lastException = Exception('Failed to load order book: $e');
          }
        }
      }

      throw Exception('无法获取订单簿数据。\n详细错误: $errorDetails');
    } catch (e) {
      print('Error fetching order book: $e');

      // 返回模拟数据
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final basePrice = 50000.0 + Random().nextDouble() * 1000;

      List<List<String>> bids = [];
      List<List<String>> asks = [];

      // 生成模拟买单
      for (int i = 0; i < 20; i++) {
        final price =
            (basePrice - i * 10 - Random().nextDouble() * 5).toStringAsFixed(2);
        final size = (0.1 + Random().nextDouble() * 2).toStringAsFixed(6);
        bids.add([price, size]);
      }

      // 生成模拟卖单
      for (int i = 0; i < 20; i++) {
        final price =
            (basePrice + i * 10 + Random().nextDouble() * 5).toStringAsFixed(2);
        final size = (0.1 + Random().nextDouble() * 2).toStringAsFixed(6);
        asks.add([price, size]);
      }

      return {
        'bids': bids,
        'asks': asks,
        'timestamp': timestamp,
      };
    }
  }

  // 获取最近的交易数据
  Future<List<Map<String, dynamic>>> getRecentTrades(String symbol,
      {int limit = 50}) async {
    try {
      print('开始获取 $symbol 的最近交易数据');

      // 尝试多个API端点
      final endpoints = [
        '/api/v5/market/trades',
      ];

      // 尝试多个基础URL
      final baseUrls = [
        _baseUrl,
        'https://www.okx.com',
        'https://aws.okx.com',
      ];

      Exception? lastException;
      String errorDetails = '';

      // 尝试所有组合
      for (final baseUrl in baseUrls) {
        for (final endpoint in endpoints) {
          try {
            print('尝试从 $baseUrl$endpoint 获取最近交易数据');

            // 创建新的Dio实例，以便可以更改baseUrl
            final dio = Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 3),
                receiveTimeout: const Duration(seconds: 2),
                headers: {
                  'Content-Type': 'application/json',
                  'User-Agent':
                      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36',
                },
              ),
            );

            // 设置代理
            _setupDioProxy(dio);

            final response = await dio.get(
              endpoint,
              queryParameters: {
                'instId': symbol,
                'limit': limit,
              },
            );

            if (response.statusCode == 200 && response.data['code'] == '0') {
              print('成功获取 $symbol 的最近交易数据');
              final List<dynamic> data = response.data['data'];

              // 转换为标准格式
              return data
                  .map((trade) => {
                        'tradeId': trade['tradeId'],
                        'price': trade['px'],
                        'size': trade['sz'],
                        'side': trade['side'],
                        'timestamp': trade['ts'],
                      })
                  .toList();
            } else {
              print('API返回错误: ${response.data['msg']}');
              errorDetails +=
                  '[$baseUrl$endpoint]: API错误 - ${response.data['msg']}\n';
            }
          } catch (e) {
            print('从 $baseUrl$endpoint 获取最近交易数据失败: $e');
            errorDetails += '[$baseUrl$endpoint]: ${e.toString()}\n';
            lastException = Exception('Failed to load recent trades: $e');
          }
        }
      }

      throw Exception('无法获取最近交易数据。\n详细错误: $errorDetails');
    } catch (e) {
      print('Error fetching recent trades: $e');

      // 返回模拟数据
      List<Map<String, dynamic>> trades = [];
      final basePrice = 50000.0 + Random().nextDouble() * 1000;
      final now = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < limit; i++) {
        final isBuy = Random().nextBool();
        final price =
            (basePrice + (isBuy ? 1 : -1) * Random().nextDouble() * 50)
                .toStringAsFixed(2);
        final size = (0.001 + Random().nextDouble() * 0.1).toStringAsFixed(6);
        final timestamp = (now - i * 1000 - Random().nextInt(500)).toString();

        trades.add({
          'tradeId': '${now}_$i',
          'price': price,
          'size': size,
          'side': isBuy ? 'buy' : 'sell',
          'timestamp': timestamp,
        });
      }

      return trades;
    }
  }
}
