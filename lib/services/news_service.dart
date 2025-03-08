import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import '../models/news.dart';
import '../models/ticker.dart';
import '../api/okx_api.dart';
import 'database_service.dart';

class NewsService {
  static final NewsService _instance = NewsService._internal();
  final Dio _dio = Dio();
  final DatabaseService _dbService = DatabaseService();
  final OkxApi _api = OkxApi();

  // 单例模式
  factory NewsService() {
    return _instance;
  }

  NewsService._internal() {
    _dio.options.headers = {
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36',
    };
  }

  // 获取OKX官方公告
  Future<List<News>> fetchOkxAnnouncements() async {
    try {
      final response = await _dio.get(
          'https://www.okx.com/support/hc/en-us/sections/360000030652-Latest-Announcements');

      if (response.statusCode == 200) {
        final document = parse(response.data);
        final articles = document.querySelectorAll('ul.article-list li');

        List<News> newsList = [];

        for (var article in articles) {
          final titleElement = article.querySelector('a');
          final dateElement = article.querySelector('time');

          if (titleElement != null && dateElement != null) {
            final title = titleElement.text.trim();
            final url = 'https://www.okx.com${titleElement.attributes['href']}';
            final dateStr = dateElement.text.trim();

            // 解析日期
            final publishedAt = _parseDate(dateStr);

            // 获取文章内容
            final content = await _fetchArticleContent(url);

            // 创建新闻对象
            final news = News(
              id: _generateNewsId(),
              title: title,
              content: content,
              source: 'OKX官方公告',
              url: url,
              publishedAt: publishedAt,
              relatedSymbols: [],
            );

            // 分析新闻内容，找出相关的虚拟币
            final newsWithRelations = await _analyzeNewsContent(news);

            newsList.add(newsWithRelations);
          }
        }

        // 保存到数据库
        await _dbService.saveMultipleNews(newsList);

        return newsList;
      } else {
        throw Exception(
            'Failed to load OKX announcements: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching OKX announcements: $e');

      // 如果获取失败，尝试从数据库加载
      final latestNews = await _dbService.getLatestNews(limit: 20);
      return latestNews
          .where((news) => news['source'] == 'OKX官方公告')
          .map((news) => News.fromJson(news))
          .toList();
    }
  }

  // 获取OKX博客文章
  Future<List<News>> fetchOkxBlogPosts() async {
    try {
      final response = await _dio
          .get('https://www.okx.com/academy/en/category/press-releases');

      if (response.statusCode == 200) {
        final document = parse(response.data);
        final articles = document.querySelectorAll('article.post');

        List<News> newsList = [];

        for (var article in articles) {
          final titleElement = article.querySelector('h2.entry-title a');
          final dateElement = article.querySelector('time.entry-date');
          final excerptElement = article.querySelector('div.entry-content');

          if (titleElement != null && dateElement != null) {
            final title = titleElement.text.trim();
            final url = titleElement.attributes['href'] ?? '';
            final dateStr = dateElement.text.trim();
            final excerpt = excerptElement?.text.trim() ?? '';

            // 解析日期
            final publishedAt = _parseDate(dateStr);

            // 获取文章内容
            final content = await _fetchArticleContent(url);

            // 创建新闻对象
            final news = News(
              id: _generateNewsId(),
              title: title,
              content: content.isNotEmpty ? content : excerpt,
              source: 'OKX博客',
              url: url,
              publishedAt: publishedAt,
              relatedSymbols: [],
            );

            // 分析新闻内容，找出相关的虚拟币
            final newsWithRelations = await _analyzeNewsContent(news);

            newsList.add(newsWithRelations);
          }
        }

        // 保存到数据库
        await _dbService.saveMultipleNews(newsList);

        return newsList;
      } else {
        throw Exception(
            'Failed to load OKX blog posts: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching OKX blog posts: $e');

      // 如果获取失败，尝试从数据库加载
      final latestNews = await _dbService.getLatestNews(limit: 20);
      return latestNews
          .where((news) => news['source'] == 'OKX博客')
          .map((news) => News.fromJson(news))
          .toList();
    }
  }

  // 获取CoinMarketCap新闻
  Future<List<News>> fetchCoinMarketCapNews() async {
    try {
      final response = await _dio
          .get('https://api.coinmarketcap.com/content/v3/news?limit=20');

      if (response.statusCode == 200) {
        final data = response.data;
        final articles = data['data'] as List;

        List<News> newsList = [];

        for (var article in articles) {
          final title = article['title'];
          final url = article['url'];
          final source = article['source'];
          final dateStr = article['createdAt'];
          final content = article['description'] ?? '';

          // 解析日期
          final publishedAt = DateTime.parse(dateStr).toIso8601String();

          // 创建新闻对象
          final news = News(
            id: _generateNewsId(),
            title: title,
            content: content,
            source: 'CoinMarketCap - $source',
            url: url,
            publishedAt: publishedAt,
            relatedSymbols: [],
          );

          // 分析新闻内容，找出相关的虚拟币
          final newsWithRelations = await _analyzeNewsContent(news);

          newsList.add(newsWithRelations);
        }

        // 保存到数据库
        await _dbService.saveMultipleNews(newsList);

        return newsList;
      } else {
        throw Exception(
            'Failed to load CoinMarketCap news: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching CoinMarketCap news: $e');

      // 如果获取失败，尝试从数据库加载
      final latestNews = await _dbService.getLatestNews(limit: 20);
      return latestNews
          .where((news) => news['source'].toString().contains('CoinMarketCap'))
          .map((news) => News.fromJson(news))
          .toList();
    }
  }

  // 获取所有新闻
  Future<List<News>> fetchAllNews() async {
    List<News> allNews = [];

    try {
      // 并行获取所有新闻源
      final results = await Future.wait([
        fetchOkxAnnouncements(),
        fetchOkxBlogPosts(),
        fetchCoinMarketCapNews(),
      ]);

      // 合并结果
      for (var newsList in results) {
        allNews.addAll(newsList);
      }

      // 按发布日期排序
      allNews.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

      return allNews;
    } catch (e) {
      print('Error fetching all news: $e');

      // 如果获取失败，尝试从数据库加载
      final latestNews = await _dbService.getLatestNews(limit: 50);
      return latestNews.map((news) => News.fromJson(news)).toList();
    }
  }

  // 获取与特定虚拟币相关的新闻
  Future<List<News>> fetchNewsBySymbol(String symbol) async {
    try {
      final newsData = await _dbService.getNewsBySymbol(symbol);
      return newsData.map((news) => News.fromJson(news)).toList();
    } catch (e) {
      print('Error fetching news for $symbol: $e');
      return [];
    }
  }

  // 解析日期字符串
  String _parseDate(String dateStr) {
    try {
      // 尝试解析常见的日期格式
      final formats = [
        'MMM d, yyyy',
        'yyyy-MM-dd',
        'dd MMM yyyy',
        'MM/dd/yyyy',
      ];

      for (var format in formats) {
        try {
          final date = DateFormat(format).parse(dateStr);
          return date.toIso8601String();
        } catch (e) {
          // 尝试下一个格式
        }
      }

      // 如果无法解析，使用当前日期
      return DateTime.now().toIso8601String();
    } catch (e) {
      print('Error parsing date: $e');
      return DateTime.now().toIso8601String();
    }
  }

  // 获取文章内容
  Future<String> _fetchArticleContent(String url) async {
    if (url.isEmpty) return '';

    try {
      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final document = parse(response.data);

        // 尝试找到文章内容
        final contentElement = document.querySelector('div.article-body') ??
            document.querySelector('div.entry-content') ??
            document.querySelector('article');

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
      print('Error fetching article content: $e');
      return '';
    }
  }

  // 分析新闻内容，找出相关的虚拟币
  Future<News> _analyzeNewsContent(News news) async {
    try {
      // 获取所有虚拟币信息
      final cryptos = await _dbService.getAllCryptocurrencies();

      if (cryptos.isEmpty) {
        // 如果数据库中没有虚拟币信息，尝试从API获取
        final instruments = await _api.getAllInstruments();

        // 保存到数据库
        await _dbService.saveCryptocurrencies(instruments.map((instrument) {
          return {
            'symbol': instrument['instId'],
            'name': instrument['baseCcy'] ?? '',
            'description': '',
          };
        }).toList());

        // 重新获取
        return await _analyzeNewsContent(news);
      }

      // 创建一个新的新闻对象，用于添加关联
      News newsWithRelations = news;

      // 检查标题和内容中是否包含虚拟币名称或符号
      for (var crypto in cryptos) {
        final symbol = crypto['symbol'] as String;
        final name = crypto['name'] as String;

        // 检查标题
        if (news.title.contains(symbol) ||
            (name.isNotEmpty && news.title.contains(name))) {
          // 获取当前价格
          String? currentPrice;
          try {
            final ticker = await _api.getTicker(symbol);
            currentPrice = ticker.currentPrice.toString();
          } catch (e) {
            print('Error fetching price for $symbol: $e');
          }

          // 如果是第一个找到的虚拟币，设置为主要关联
          if (newsWithRelations.relatedSymbols.isEmpty) {
            // 添加关联
            final updatedRelations = [
              NewsSymbolRelation(
                symbol: symbol,
                priceAtPublish:
                    currentPrice != null ? double.tryParse(currentPrice) : null,
                priceChange24h: null,
              )
            ];

            newsWithRelations = News(
              id: newsWithRelations.id,
              title: newsWithRelations.title,
              content: newsWithRelations.content,
              source: newsWithRelations.source,
              url: newsWithRelations.url,
              publishedAt: newsWithRelations.publishedAt,
              relatedSymbols: updatedRelations,
            );
          }
        }

        // 检查内容
        else if (news.content.contains(symbol) ||
            (name.isNotEmpty && news.content.contains(name))) {
          // 获取当前价格
          String? currentPrice;
          try {
            final ticker = await _api.getTicker(symbol);
            currentPrice = ticker.currentPrice.toString();
          } catch (e) {
            print('Error fetching price for $symbol: $e');
          }

          // 如果是第一个找到的虚拟币，设置为主要关联
          if (newsWithRelations.relatedSymbols.isEmpty) {
            // 添加关联
            final updatedRelations = [
              NewsSymbolRelation(
                symbol: symbol,
                priceAtPublish:
                    currentPrice != null ? double.tryParse(currentPrice) : null,
                priceChange24h: null,
              )
            ];

            newsWithRelations = News(
              id: newsWithRelations.id,
              title: newsWithRelations.title,
              content: newsWithRelations.content,
              source: newsWithRelations.source,
              url: newsWithRelations.url,
              publishedAt: newsWithRelations.publishedAt,
              relatedSymbols: updatedRelations,
            );
          }
        }
      }

      return newsWithRelations;
    } catch (e) {
      print('Error analyzing news content: $e');
      return news;
    }
  }

  // 从OKX博客获取新闻
  Future<List<News>> fetchOkxBlogNews() async {
    try {
      final response = await _dio.get('https://www.okx.com/academy/zh/blog');

      if (response.statusCode == 200) {
        final document = parse(response.data);
        final articles = document.querySelectorAll('article');

        final List<News> newsList = [];

        for (var article in articles) {
          final titleElement = article.querySelector('.post-title a');
          final contentElement = article.querySelector('.post-excerpt');
          final dateElement = article.querySelector('.post-date');

          if (titleElement != null && contentElement != null) {
            final title = titleElement.text.trim();
            final content = contentElement.text.trim();
            final url = titleElement.attributes['href'] ?? '';
            final publishedAt =
                dateElement?.text.trim() ?? DateTime.now().toIso8601String();

            final news = News(
              id: _generateNewsId(),
              title: title,
              content: content,
              source: 'OKX博客',
              publishedAt: publishedAt,
              url: url,
              relatedSymbols: [],
            );

            newsList.add(news);
          }
        }

        return newsList;
      } else {
        throw Exception('获取OKX博客新闻失败: ${response.statusCode}');
      }
    } catch (e) {
      print('获取OKX博客新闻出错: $e');
      return [];
    }
  }

  // 从OKX公告获取新闻
  Future<List<News>> fetchOkxAnnouncementNews() async {
    try {
      final response = await _dio
          .get('https://www.okx.com/support/hc/zh-cn/sections/360000030652');

      if (response.statusCode == 200) {
        final document = parse(response.data);
        final articles = document.querySelectorAll('.article-list-item');

        final List<News> newsList = [];

        for (var article in articles) {
          final titleElement = article.querySelector('a');
          final dateElement = article.querySelector('.article-list-item__date');

          if (titleElement != null) {
            final title = titleElement.text.trim();
            final url = titleElement.attributes['href'] ?? '';
            final publishedAt =
                dateElement?.text.trim() ?? DateTime.now().toIso8601String();

            // 获取文章内容
            String content = '';
            try {
              final articleResponse = await _dio.get(url);
              if (articleResponse.statusCode == 200) {
                final articleDocument = parse(articleResponse.data);
                final contentElement =
                    articleDocument.querySelector('.article__content');
                if (contentElement != null) {
                  content = contentElement.text.trim();
                }
              }
            } catch (e) {
              print('获取文章内容出错: $e');
            }

            final news = News(
              id: _generateNewsId(),
              title: title,
              content: content.isEmpty ? '点击查看详情' : content,
              source: 'OKX官方公告',
              publishedAt: publishedAt,
              url: url,
              relatedSymbols: [],
            );

            newsList.add(news);
          }
        }

        return newsList;
      } else {
        throw Exception('获取OKX公告新闻失败: ${response.statusCode}');
      }
    } catch (e) {
      print('获取OKX公告新闻出错: $e');
      return [];
    }
  }

  // 生成唯一的新闻ID
  String _generateNewsId() {
    return 'news_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  // 将新闻与虚拟币关联
  Future<News> associateNewsWithCrypto(
      News news, String symbol, String? price) async {
    try {
      // 创建一个新的News对象，包含关联的虚拟币
      final updatedNews = News(
        id: news.id,
        title: news.title,
        content: news.content,
        source: news.source,
        publishedAt: news.publishedAt,
        url: news.url,
        relatedSymbols: [
          ...news.relatedSymbols,
          NewsSymbolRelation(
            symbol: symbol,
            priceAtPublish: price != null ? double.tryParse(price) : null,
            priceChange24h: null,
          ),
        ],
      );

      // 保存到数据库
      await _dbService.saveNews(updatedNews);

      return updatedNews;
    } catch (e) {
      print('关联新闻与虚拟币失败: $e');
      rethrow;
    }
  }
}
