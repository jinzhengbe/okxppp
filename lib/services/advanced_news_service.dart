import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/news.dart';
import '../models/ticker.dart';
import '../api/okx_api.dart';
import 'database_service.dart';
import 'news_service.dart';

class AdvancedNewsService {
  static final AdvancedNewsService _instance = AdvancedNewsService._internal();
  final Dio _dio = Dio();
  final DatabaseService _dbService = DatabaseService();
  final OkxApi _okxApi = OkxApi();
  final NewsService _newsService = NewsService();

  // 搜索引擎API密钥
  String? _googleApiKey;
  String? _googleSearchEngineId;

  // 暗网代理设置
  bool _useTorProxy = false;
  String _torProxyHost = '127.0.0.1';
  int _torProxyPort = 9050;

  // 上次搜索时间
  DateTime? _lastSearchTime;

  // 单例模式
  factory AdvancedNewsService() {
    return _instance;
  }

  AdvancedNewsService._internal() {
    _dio.options.headers = {
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36',
    };

    // 加载配置
    _loadConfig();
  }

  // 加载配置
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();

    // 加载API密钥
    _googleApiKey = prefs.getString('google_api_key');
    _googleSearchEngineId = prefs.getString('google_search_engine_id');

    // 加载暗网代理设置
    _useTorProxy = prefs.getBool('use_tor_proxy') ?? false;
    _torProxyHost = prefs.getString('tor_proxy_host') ?? '127.0.0.1';
    _torProxyPort = prefs.getInt('tor_proxy_port') ?? 9050;

    // 加载上次搜索时间
    final lastSearchTimeStr = prefs.getString('last_news_search_time');
    if (lastSearchTimeStr != null) {
      _lastSearchTime = DateTime.parse(lastSearchTimeStr);
    }
  }

  // 保存配置
  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();

    // 保存API密钥
    if (_googleApiKey != null) {
      await prefs.setString('google_api_key', _googleApiKey!);
    }
    if (_googleSearchEngineId != null) {
      await prefs.setString('google_search_engine_id', _googleSearchEngineId!);
    }

    // 保存暗网代理设置
    await prefs.setBool('use_tor_proxy', _useTorProxy);
    await prefs.setString('tor_proxy_host', _torProxyHost);
    await prefs.setInt('tor_proxy_port', _torProxyPort);

    // 保存上次搜索时间
    if (_lastSearchTime != null) {
      await prefs.setString(
          'last_news_search_time', _lastSearchTime!.toIso8601String());
    }
  }

  // 设置Google API密钥
  Future<void> setGoogleApiKey(String apiKey, String searchEngineId) async {
    _googleApiKey = apiKey;
    _googleSearchEngineId = searchEngineId;
    await _saveConfig();
  }

  // 设置暗网代理
  Future<void> setTorProxy(bool useTorProxy, String host, int port) async {
    _useTorProxy = useTorProxy;
    _torProxyHost = host;
    _torProxyPort = port;
    await _saveConfig();
  }

  // 获取所有虚拟币符号
  Future<List<String>> getAllCryptoSymbols() async {
    try {
      // 从数据库获取所有虚拟币信息
      final cryptos = await _dbService.getAllCryptocurrencies();

      if (cryptos.isEmpty) {
        // 如果数据库中没有虚拟币信息，尝试从API获取
        final instruments = await _okxApi.getAllInstruments();

        // 保存到数据库
        await _dbService.saveCryptocurrencies(instruments.map((instrument) {
          return {
            'symbol': instrument['instId'],
            'name': instrument['baseCcy'] ?? '',
            'description': '',
          };
        }).toList());

        // 重新获取
        return await getAllCryptoSymbols();
      }

      // 提取所有符号
      return cryptos.map((crypto) => crypto['symbol'] as String).toList();
    } catch (e) {
      print('获取虚拟币符号失败: $e');
      return [];
    }
  }

  // 从Google搜索虚拟币新闻
  Future<List<News>> searchGoogleNews(String query,
      {int maxResults = 10}) async {
    if (_googleApiKey == null || _googleSearchEngineId == null) {
      throw Exception('Google API密钥未设置');
    }

    try {
      final response = await _dio.get(
        'https://www.googleapis.com/customsearch/v1',
        queryParameters: {
          'key': _googleApiKey,
          'cx': _googleSearchEngineId,
          'q': query,
          'num': maxResults,
          'sort': 'date',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final items = data['items'] as List?;

        if (items == null || items.isEmpty) {
          return [];
        }

        List<News> newsList = [];

        for (var item in items) {
          final title = item['title'];
          final snippet = item['snippet'];
          final link = item['link'];
          final source = item['displayLink'] ?? 'Google Search';

          // 获取完整内容
          String content = snippet;
          try {
            final fullContent = await _fetchArticleContent(link);
            if (fullContent.isNotEmpty) {
              content = fullContent;
            }
          } catch (e) {
            print('获取文章内容失败: $e');
          }

          // 创建新闻对象
          final news = News(
            id: _generateNewsId(),
            title: title,
            content: content,
            source: 'Google - $source',
            url: link,
            publishedAt: DateTime.now().toIso8601String(),
            relatedSymbols: [],
          );

          // 分析新闻内容，找出相关的虚拟币
          final newsWithRelations = await _analyzeNewsContent(news);

          newsList.add(newsWithRelations);
        }

        return newsList;
      } else {
        throw Exception('Google搜索失败: ${response.statusCode}');
      }
    } catch (e) {
      print('Google搜索错误: $e');
      return [];
    }
  }

  // 从暗网搜索虚拟币新闻
  Future<List<News>> searchDarkWebNews(String query,
      {int maxResults = 5}) async {
    if (!_useTorProxy) {
      throw Exception('暗网代理未启用');
    }

    try {
      // 创建带有SOCKS5代理的Dio实例
      final proxyDio = Dio();

      // 设置SOCKS5代理
      (proxyDio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate =
          (client) {
        client.findProxy = (uri) {
          return 'SOCKS5 $_torProxyHost:$_torProxyPort';
        };
        return client;
      };

      // 暗网搜索引擎列表（这些是示例，实际使用时需要替换为有效的暗网搜索引擎）
      final darkWebSearchEngines = [
        'http://searchcoaupi3csb.onion/search.php?q=$query',
        'http://gjobqjj7wyczbqie.onion/search?q=$query',
        'http://hss3uro2hsxfogfq.onion/index.php?q=$query',
      ];

      List<News> allNews = [];

      for (var searchUrl in darkWebSearchEngines) {
        try {
          // 通过SOCKS5代理发送请求
          final response = await proxyDio.get(searchUrl);

          if (response.statusCode == 200) {
            final document = html_parser.parse(response.data);
            final results =
                document.querySelectorAll('div.result, div.search-result');

            for (var result in results.take(maxResults)) {
              final titleElement = result.querySelector('h3, h2, .title');
              final linkElement = result.querySelector('a');
              final snippetElement =
                  result.querySelector('div.snippet, div.description, p');

              if (titleElement != null && linkElement != null) {
                final title = titleElement.text.trim();
                final link = linkElement.attributes['href'] ?? '';
                final snippet = snippetElement?.text.trim() ?? '';

                // 创建新闻对象
                final news = News(
                  id: _generateNewsId(),
                  title: title,
                  content: snippet,
                  source: 'DarkWeb - ${Uri.parse(searchUrl).host}',
                  url: link,
                  publishedAt: DateTime.now().toIso8601String(),
                  relatedSymbols: [],
                );

                // 分析新闻内容，找出相关的虚拟币
                final newsWithRelations = await _analyzeNewsContent(news);

                allNews.add(newsWithRelations);
              }
            }
          }
        } catch (e) {
          print('暗网搜索错误 (${Uri.parse(searchUrl).host}): $e');
        }
      }

      return allNews;
    } catch (e) {
      print('暗网搜索错误: $e');
      return [];
    }
  }

  // 获取文章内容
  Future<String> _fetchArticleContent(String url) async {
    if (url.isEmpty) return '';

    try {
      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.data);

        // 尝试找到文章内容
        final contentElement = document.querySelector('article') ??
            document.querySelector('div.article-body') ??
            document.querySelector('div.entry-content') ??
            document.querySelector('div.content');

        if (contentElement != null) {
          // 移除脚本和样式标签
          contentElement.querySelectorAll('script, style').forEach((element) {
            element.remove();
          });

          return contentElement.text.trim();
        }
      }

      return '';
    } catch (e) {
      print('获取文章内容错误: $e');
      return '';
    }
  }

  // 分析新闻内容，找出相关的虚拟币
  Future<News> _analyzeNewsContent(News news) async {
    try {
      // 定义常见的加密货币符号
      final cryptoSymbols = [
        'BTC',
        'ETH',
        'USDT',
        'BNB',
        'XRP',
        'ADA',
        'SOL',
        'DOT',
        'DOGE',
        'SHIB',
        'AVAX',
        'MATIC',
        'LTC',
        'LINK',
        'UNI',
        'ALGO',
        'XLM',
        'ATOM',
        'VET',
        'FIL'
      ];

      // 创建一个新的关联列表
      List<NewsSymbolRelation> relatedSymbols =
          List<NewsSymbolRelation>.from(news.relatedSymbols);

      // 检查标题和内容中是否包含加密货币符号
      for (var symbol in cryptoSymbols) {
        if (news.title.contains(symbol) || news.content.contains(symbol)) {
          // 获取当前价格
          double? price;
          try {
            // 尝试不同的交易对格式
            List<String> tradingPairs = [
              '$symbol-USDT',
              '$symbol-USD',
              '$symbol-USDC'
            ];
            Ticker? ticker;

            for (var pair in tradingPairs) {
              try {
                ticker = await _okxApi.getTicker(pair);
                if (ticker != null) break;
              } catch (e) {
                print('尝试获取 $pair 价格失败: $e');
                // 继续尝试下一个交易对
              }
            }

            if (ticker != null) {
              price = ticker.currentPrice;
            }
          } catch (e) {
            print('获取 $symbol 价格失败: $e');
            // 继续处理，不中断流程
          }

          // 检查是否已经存在该关联
          final existingIndex = relatedSymbols
              .indexWhere((relation) => relation.symbol == symbol);

          if (existingIndex >= 0) {
            // 更新现有关联
            relatedSymbols[existingIndex] = NewsSymbolRelation(
              symbol: symbol,
              priceAtPublish: price,
              priceChange24h: null,
            );
          } else {
            // 添加新关联
            relatedSymbols.add(NewsSymbolRelation(
              symbol: symbol,
              priceAtPublish: price,
              priceChange24h: null,
            ));
          }
        }
      }

      // 如果找到了相关的加密货币，创建一个新的News对象
      if (relatedSymbols.isNotEmpty) {
        return News(
          id: news.id,
          title: news.title,
          content: news.content,
          source: news.source,
          publishedAt: news.publishedAt,
          url: news.url,
          relatedSymbols: relatedSymbols,
        );
      }

      // 如果没有找到相关的加密货币，返回原始新闻
      return news;
    } catch (e) {
      print('分析新闻内容失败: $e');
      return news;
    }
  }

  // 执行每日新闻搜索
  Future<List<News>> performDailyNewsSearch() async {
    try {
      // 检查上次搜索时间，避免频繁搜索
      final lastSearchTime = await _loadLastSearchTime();
      final now = DateTime.now();

      if (lastSearchTime != null) {
        final difference = now.difference(lastSearchTime);
        if (difference.inHours < 24) {
          // 如果距离上次搜索不到24小时，则从数据库加载新闻
          final newsData = await _dbService.getLatestNews(limit: 100);
          return newsData.map((news) => News.fromJson(news)).toList();
        }
      }

      // 定义要搜索的虚拟币符号
      final cryptoSymbols = await getAllCryptoSymbols();
      if (cryptoSymbols.isEmpty) {
        throw Exception('没有找到虚拟币符号');
      }

      List<News> allNews = [];

      // 对每个虚拟币进行搜索
      for (var symbol in cryptoSymbols.take(10)) {
        // 限制搜索数量，避免API请求过多
        // 添加延迟，避免API请求过于频繁
        await Future.delayed(Duration(seconds: 2));

        // 从Google搜索新闻
        try {
          final googleNews = await searchGoogleNews(
              '$symbol cryptocurrency news',
              maxResults: 5);

          // 分析每条新闻
          for (var news in googleNews) {
            // 检查是否已存在相同标题的新闻
            final existingNews =
                allNews.where((n) => n.title == news.title).toList();
            if (existingNews.isEmpty) {
              // 分析新闻内容
              final analyzedNews = await _analyzeNewsContent(news);

              // 保存到数据库
              await _dbService.saveNews(analyzedNews);

              allNews.add(analyzedNews);
            }
          }
        } catch (e) {
          print('Google搜索 $symbol 新闻失败: $e');
        }

        // 如果启用了暗网代理，也从暗网搜索新闻
        if (_useTorProxy) {
          try {
            final darkWebNews =
                await searchDarkWebNews('$symbol crypto', maxResults: 2);

            // 分析每条新闻
            for (var news in darkWebNews) {
              // 检查是否已存在相同标题的新闻
              final existingNews =
                  allNews.where((n) => n.title == news.title).toList();
              if (existingNews.isEmpty) {
                // 分析新闻内容
                final analyzedNews = await _analyzeNewsContent(news);

                // 保存到数据库
                await _dbService.saveNews(analyzedNews);

                allNews.add(analyzedNews);
              }
            }
          } catch (e) {
            print('暗网搜索 $symbol 新闻失败: $e');
          }
        }
      }

      // 更新上次搜索时间
      await _saveLastSearchTime(now);

      return allNews;
    } catch (e) {
      print('执行每日新闻搜索失败: $e');
      rethrow;
    }
  }

  // 启动定时搜索任务
  void startScheduledSearch() {
    // 每天执行一次搜索
    Timer.periodic(Duration(hours: 24), (timer) {
      performDailyNewsSearch();
    });
  }

  // 将新闻与虚拟币关联
  Future<News> associateNewsWithCrypto(
      News news, String symbol, String? price) async {
    try {
      // 创建一个新的News对象，包含关联的虚拟币
      final existingRelations =
          List<NewsSymbolRelation>.from(news.relatedSymbols);

      // 检查是否已经存在该关联
      final existingIndex =
          existingRelations.indexWhere((relation) => relation.symbol == symbol);

      if (existingIndex >= 0) {
        // 更新现有关联
        existingRelations[existingIndex] = NewsSymbolRelation(
          symbol: symbol,
          priceAtPublish: price != null ? double.tryParse(price) : null,
          priceChange24h: null,
        );
      } else {
        // 添加新关联
        existingRelations.add(NewsSymbolRelation(
          symbol: symbol,
          priceAtPublish: price != null ? double.tryParse(price) : null,
          priceChange24h: null,
        ));
      }

      // 创建更新后的新闻对象
      final updatedNews = News(
        id: news.id,
        title: news.title,
        content: news.content,
        source: news.source,
        publishedAt: news.publishedAt,
        url: news.url,
        relatedSymbols: existingRelations,
      );

      // 保存到数据库
      await _dbService.saveNews(updatedNews);

      return updatedNews;
    } catch (e) {
      print('关联新闻与虚拟币失败: $e');
      rethrow;
    }
  }

  // 生成唯一的新闻ID
  String _generateNewsId() {
    return 'news_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  // 保存上次搜索时间
  Future<void> _saveLastSearchTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_news_search_time', time.toIso8601String());
  }

  // 加载上次搜索时间
  Future<DateTime?> _loadLastSearchTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSearchTimeStr = prefs.getString('last_news_search_time');
    if (lastSearchTimeStr != null) {
      return DateTime.parse(lastSearchTimeStr);
    }
    return null;
  }

  // 获取所有新闻影响分析
  Future<Map<String, List<Map<String, dynamic>>>>
      getAllNewsImpactAnalysis() async {
    try {
      // 从数据库获取所有新闻
      final newsData = await _dbService.getLatestNews(limit: 100);

      // 创建结果映射
      final Map<String, List<Map<String, dynamic>>> result = {};

      // 如果没有新闻数据，返回模拟数据
      if (newsData.isEmpty) {
        print('数据库中没有新闻数据，返回模拟数据');
        return _getMockNewsImpactAnalysis();
      }

      // 解析新闻数据
      List<News> newsList = [];
      for (var newsItem in newsData) {
        try {
          final news = News.fromJson(newsItem);
          newsList.add(news);
        } catch (e) {
          print('解析新闻数据失败: $e');
          // 继续处理下一条新闻
        }
      }

      print('成功解析 ${newsList.length} 条新闻');

      // 按虚拟币符号分组
      for (var news in newsList) {
        try {
          // 跳过没有关联虚拟币的新闻
          if (news.relatedSymbols.isEmpty) continue;

          for (var relation in news.relatedSymbols) {
            final symbol = relation.symbol;

            // 计算影响分数（这里使用简单算法，实际应用中可能需要更复杂的分析）
            double impactScore = 0;
            String sentiment = 'neutral';

            // 分析新闻内容，计算情感分数
            final content = news.title + ' ' + news.content;
            final lowerContent = content.toLowerCase();

            // 积极词汇
            final positiveWords = [
              'up',
              'rise',
              'rising',
              'bull',
              'bullish',
              'gain',
              'gains',
              'positive',
              'increase',
              'increasing',
              'growth',
              'growing',
              'rally',
              'rallying',
              'outperform',
              'outperforming',
              'strong',
              'stronger',
              'strength',
              'opportunity',
              'opportunities',
              'potential',
              'success',
              'successful',
              'profit',
              'profitable',
              'win',
              'winning',
              'good',
              'great',
              'excellent',
              'impressive',
              'breakthrough',
              'innovation',
              'innovative',
              'progress',
              'progressive',
              'advance',
              'advancing',
              'improvement',
              'improving',
              'optimistic',
              'optimism',
              'confidence',
              'confident',
              'support',
              'supporting',
              'backed',
              'backing',
              'partnership',
              'collaboration',
              '上涨',
              '涨',
              '看涨',
              '牛市',
              '增长',
              '增加',
              '提高',
              '积极',
              '强劲',
              '机会',
              '潜力',
              '成功',
              '盈利',
              '突破',
              '创新',
              '进步',
              '乐观',
              '信心',
              '支持',
              '合作'
            ];

            // 消极词汇
            final negativeWords = [
              'down',
              'fall',
              'falling',
              'bear',
              'bearish',
              'loss',
              'losses',
              'negative',
              'decrease',
              'decreasing',
              'decline',
              'declining',
              'drop',
              'dropping',
              'underperform',
              'underperforming',
              'weak',
              'weaker',
              'weakness',
              'risk',
              'risks',
              'risky',
              'danger',
              'dangerous',
              'threat',
              'threatening',
              'problem',
              'problematic',
              'issue',
              'issues',
              'concern',
              'concerning',
              'worry',
              'worrying',
              'fear',
              'fearful',
              'panic',
              'crash',
              'crashing',
              'collapse',
              'collapsing',
              'plunge',
              'plunging',
              'tumble',
              'tumbling',
              'struggle',
              'struggling',
              'pressure',
              'pressured',
              'sell',
              'selling',
              'dump',
              'dumping',
              'liquidation',
              'liquidating',
              'ban',
              'banning',
              'regulation',
              'regulating',
              'restriction',
              'restricting',
              'fraud',
              'fraudulent',
              'scam',
              'hack',
              'hacked',
              'attack',
              'vulnerability',
              '下跌',
              '跌',
              '看跌',
              '熊市',
              '减少',
              '降低',
              '消极',
              '疲软',
              '风险',
              '危险',
              '威胁',
              '问题',
              '担忧',
              '恐慌',
              '崩溃',
              '暴跌',
              '挣扎',
              '压力',
              '抛售',
              '倾销',
              '清算',
              '禁止',
              '监管',
              '限制',
              '欺诈',
              '骗局',
              '黑客',
              '攻击',
              '漏洞'
            ];

            // 计算积极和消极词汇出现的次数
            int positiveCount = 0;
            int negativeCount = 0;

            for (var word in positiveWords) {
              positiveCount +=
                  _countOccurrences(lowerContent, word.toLowerCase());
            }

            for (var word in negativeWords) {
              negativeCount +=
                  _countOccurrences(lowerContent, word.toLowerCase());
            }

            // 计算情感分数
            if (positiveCount > negativeCount) {
              sentiment = 'positive';
              impactScore = 0.5 + (positiveCount - negativeCount) * 0.1;
              if (impactScore > 5) impactScore = 5;
            } else if (negativeCount > positiveCount) {
              sentiment = 'negative';
              impactScore = -0.5 - (negativeCount - positiveCount) * 0.1;
              if (impactScore < -5) impactScore = -5;
            }

            // 如果新闻来源是官方公告，增加影响力
            if (news.source.contains('官方') || news.source.contains('OKX')) {
              impactScore *= 1.5;
            }

            // 添加到结果中
            if (!result.containsKey(symbol)) {
              result[symbol] = [];
            }

            result[symbol]!.add({
              'news': news,
              'impact_score': impactScore,
              'sentiment': sentiment,
            });
          }
        } catch (e) {
          print('处理新闻 ${news.id} 失败: $e');
          // 继续处理下一条新闻
        }
      }

      // 对每个符号的新闻按影响分数排序
      for (var symbol in result.keys) {
        result[symbol]!.sort((a, b) {
          return (b['impact_score'] as double)
              .abs()
              .compareTo((a['impact_score'] as double).abs());
        });
      }

      return result;
    } catch (e) {
      print('获取新闻影响分析失败: $e');
      return {};
    }
  }

  // 生成模拟的新闻影响分析数据
  Map<String, List<Map<String, dynamic>>> _getMockNewsImpactAnalysis() {
    final Map<String, List<Map<String, dynamic>>> result = {};

    // 创建一些模拟的加密货币符号
    final symbols = ['BTC', 'ETH', 'SOL', 'DOGE', 'XRP'];

    // 为每个符号创建一些模拟的新闻影响分析
    for (var symbol in symbols) {
      result[symbol] = [];

      // 添加一些积极的新闻
      result[symbol]!.add({
        'news': News(
          id: 'mock_${symbol}_positive_1',
          title: '$symbol 价格上涨，市场看好未来发展',
          content:
              '今日，$symbol 价格大幅上涨，涨幅超过10%。分析师认为，这主要是由于机构投资者的持续进入和市场流动性增加所致。多个技术指标显示，$symbol 可能会在短期内继续上涨。',
          source: 'CryptoNews',
          publishedAt:
              DateTime.now().subtract(Duration(hours: 5)).toIso8601String(),
          url: 'https://example.com/crypto-news',
          relatedSymbols: [
            NewsSymbolRelation(
              symbol: symbol,
              priceAtPublish: 50000.0,
              priceChange24h: 10.5,
            ),
          ],
        ),
        'impact_score': 3.5,
        'sentiment': 'positive',
      });

      // 添加一些消极的新闻
      result[symbol]!.add({
        'news': News(
          id: 'mock_${symbol}_negative_1',
          title: '$symbol 面临监管压力，价格下跌',
          content:
              '据报道，多个国家正在考虑对包括 $symbol 在内的加密货币实施更严格的监管。这一消息导致 $symbol 价格在过去24小时内下跌了8%。市场参与者担忧，这可能会影响 $symbol 的长期发展。',
          source: 'CryptoDaily',
          publishedAt:
              DateTime.now().subtract(Duration(hours: 12)).toIso8601String(),
          url: 'https://example.com/crypto-daily',
          relatedSymbols: [
            NewsSymbolRelation(
              symbol: symbol,
              priceAtPublish: 48000.0,
              priceChange24h: -8.0,
            ),
          ],
        ),
        'impact_score': -2.8,
        'sentiment': 'negative',
      });

      // 添加一些中性的新闻
      result[symbol]!.add({
        'news': News(
          id: 'mock_${symbol}_neutral_1',
          title: '$symbol 社区讨论技术升级',
          content:
              '$symbol 社区正在讨论一项技术升级提案，该提案旨在提高网络的可扩展性和安全性。目前，社区对此存在不同意见，尚未达成共识。市场对此反应平淡，$symbol 价格基本保持稳定。',
          source: 'BlockchainNews',
          publishedAt:
              DateTime.now().subtract(Duration(days: 1)).toIso8601String(),
          url: 'https://example.com/blockchain-news',
          relatedSymbols: [
            NewsSymbolRelation(
              symbol: symbol,
              priceAtPublish: 49500.0,
              priceChange24h: 0.2,
            ),
          ],
        ),
        'impact_score': 0.1,
        'sentiment': 'neutral',
      });
    }

    return result;
  }

  // 计算字符串中某个词出现的次数
  int _countOccurrences(String text, String word) {
    if (word.isEmpty) return 0;

    int count = 0;
    int index = 0;
    while (true) {
      index = text.indexOf(word, index);
      if (index == -1) break;
      count++;
      index += word.length;
    }
    return count;
  }
}
