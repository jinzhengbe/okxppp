import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/ticker.dart';
import '../models/news.dart';
import 'dart:convert';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  // 单例模式
  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // 初始化数据库
  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'crypto_data.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    // 创建价格表
    await db.execute('''
      CREATE TABLE tickers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        symbol TEXT NOT NULL,
        price TEXT NOT NULL,
        change_percentage TEXT NOT NULL,
        volume TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 创建虚拟币信息表
    await db.execute('''
      CREATE TABLE cryptocurrencies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        symbol TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 创建新闻表
    await db.execute('''
      CREATE TABLE news (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        source TEXT NOT NULL,
        url TEXT,
        published_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        related_symbols TEXT
      )
    ''');

    // 创建新闻-虚拟币关系表
    await db.execute('''
      CREATE TABLE news_crypto_relation (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        news_id INTEGER NOT NULL,
        symbol TEXT NOT NULL,
        price_at_publish TEXT,
        FOREIGN KEY (news_id) REFERENCES news (id) ON DELETE CASCADE,
        UNIQUE(news_id, symbol)
      )
    ''');
  }

  // 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 添加虚拟币信息表
      await db.execute('''
        CREATE TABLE cryptocurrencies (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          symbol TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          description TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      // 添加新闻表
      await db.execute('''
        CREATE TABLE news (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          source TEXT NOT NULL,
          url TEXT,
          published_at TEXT NOT NULL,
          created_at TEXT NOT NULL,
          related_symbols TEXT
        )
      ''');

      // 添加新闻-虚拟币关系表
      await db.execute('''
        CREATE TABLE news_crypto_relation (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          news_id INTEGER NOT NULL,
          symbol TEXT NOT NULL,
          price_at_publish TEXT,
          FOREIGN KEY (news_id) REFERENCES news (id) ON DELETE CASCADE,
          UNIQUE(news_id, symbol)
        )
      ''');
    }
  }

  // 保存Ticker数据
  Future<int> saveTicker(Ticker ticker) async {
    final db = await database;
    return await db.insert(
      'tickers',
      {
        'symbol': ticker.symbol,
        'price': ticker.currentPrice.toString(),
        'change_percentage': ticker.changePercentage.toString(),
        'volume': ticker.volume.toString(),
        'timestamp': ticker.timestamp,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 批量保存Ticker数据
  Future<void> saveTickers(List<Ticker> tickers) async {
    final db = await database;
    final batch = db.batch();

    for (var ticker in tickers) {
      batch.insert(
        'tickers',
        {
          'symbol': ticker.symbol,
          'price': ticker.currentPrice.toString(),
          'change_percentage': ticker.changePercentage.toString(),
          'volume': ticker.volume.toString(),
          'timestamp': ticker.timestamp,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // 获取特定交易对的历史数据
  Future<List<Map<String, dynamic>>> getTickerHistory(String symbol,
      {int limit = 100}) async {
    final db = await database;
    return await db.query(
      'tickers',
      where: 'symbol = ?',
      whereArgs: [symbol],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  // 获取所有交易对的最新数据
  Future<List<Map<String, dynamic>>> getLatestTickers() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT t1.* 
      FROM tickers t1
      JOIN (
        SELECT symbol, MAX(created_at) as max_date
        FROM tickers
        GROUP BY symbol
      ) t2
      ON t1.symbol = t2.symbol AND t1.created_at = t2.max_date
      ORDER BY t1.symbol
    ''');
  }

  // 保存虚拟币信息
  Future<int> saveCryptocurrency(Map<String, dynamic> crypto) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    return await db.insert(
      'cryptocurrencies',
      {
        'symbol': crypto['symbol'],
        'name': crypto['name'],
        'description': crypto['description'] ?? '',
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 批量保存虚拟币信息
  Future<void> saveCryptocurrencies(List<Map<String, dynamic>> cryptos) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();

    for (var crypto in cryptos) {
      batch.insert(
        'cryptocurrencies',
        {
          'symbol': crypto['symbol'],
          'name': crypto['name'],
          'description': crypto['description'] ?? '',
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  // 获取所有虚拟币信息
  Future<List<Map<String, dynamic>>> getAllCryptocurrencies() async {
    final db = await database;
    return await db.query('cryptocurrencies', orderBy: 'symbol');
  }

  // 保存新闻到数据库
  Future<void> saveNews(News news) async {
    try {
      final db = await database;

      // 检查新闻是否已存在
      final existingNews = await db.query(
        'news',
        where: 'title = ?',
        whereArgs: [news.title],
      );

      if (existingNews.isEmpty) {
        // 插入新闻
        await db.insert(
          'news',
          {
            'id': news.id,
            'title': news.title,
            'content': news.content,
            'source': news.source,
            'published_at': news.publishedAt,
            'url': news.url ?? '',
            // 将相关虚拟币保存为JSON字符串
            'related_symbols':
                jsonEncode(news.relatedSymbols.map((e) => e.toJson()).toList()),
          },
        );
      } else {
        // 更新现有新闻
        await db.update(
          'news',
          {
            'content': news.content,
            'source': news.source,
            'published_at': news.publishedAt,
            'url': news.url ?? '',
            // 将相关虚拟币保存为JSON字符串
            'related_symbols':
                jsonEncode(news.relatedSymbols.map((e) => e.toJson()).toList()),
          },
          where: 'title = ?',
          whereArgs: [news.title],
        );
      }
    } catch (e) {
      print('保存新闻失败: $e');
      rethrow;
    }
  }

  // 批量保存新闻
  Future<void> saveMultipleNews(List<News> newsList) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();

    for (var news in newsList) {
      // 插入新闻
      final newsId = await db.insert(
        'news',
        {
          'title': news.title,
          'content': news.content,
          'source': news.source,
          'url': news.url ?? '',
          'published_at': news.publishedAt,
          'created_at': now,
          'related_symbols':
              jsonEncode(news.relatedSymbols.map((e) => e.toJson()).toList()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 如果有关联的虚拟币，保存关系
      if (news.relatedSymbols.isNotEmpty) {
        for (var relation in news.relatedSymbols) {
          batch.insert(
            'news_crypto_relation',
            {
              'news_id': newsId,
              'symbol': relation.symbol,
              'price_at_publish': relation.priceAtPublish ?? '',
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    }

    await batch.commit(noResult: true);
  }

  // 从数据库获取最新新闻
  Future<List<Map<String, dynamic>>> getLatestNews({int limit = 20}) async {
    try {
      final db = await database;

      final newsData = await db.query(
        'news',
        orderBy: 'published_at DESC',
        limit: limit,
      );

      // 将数据库记录转换为可用于创建News对象的映射
      return newsData.map((record) {
        // 解析相关虚拟币JSON字符串
        List<dynamic> relatedSymbolsJson = [];
        try {
          if (record['related_symbols'] != null &&
              record['related_symbols'].toString().isNotEmpty) {
            relatedSymbolsJson =
                jsonDecode(record['related_symbols'].toString());
          }
        } catch (e) {
          print('解析相关虚拟币JSON失败: $e');
        }

        return {
          'id': record['id'],
          'title': record['title'],
          'content': record['content'],
          'source': record['source'],
          'published_at': record['published_at'],
          'url': record['url'],
          'related_symbols': relatedSymbolsJson,
        };
      }).toList();
    } catch (e) {
      print('获取最新新闻失败: $e');
      return [];
    }
  }

  // 获取与特定虚拟币相关的新闻
  Future<List<Map<String, dynamic>>> getNewsBySymbol(String symbol,
      {int limit = 20}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT n.* 
      FROM news n
      LEFT JOIN news_crypto_relation r ON n.id = r.news_id
      WHERE n.related_symbols LIKE ? OR r.symbol = ?
      ORDER BY n.published_at DESC
      LIMIT ?
    ''', ['$symbol%', symbol, limit]);
  }

  // 获取新闻的相关虚拟币
  Future<List<Map<String, dynamic>>> getNewsRelatedCryptos(int newsId) async {
    final db = await database;
    return await db.query(
      'news_crypto_relation',
      where: 'news_id = ?',
      whereArgs: [newsId],
    );
  }

  // 清除旧数据（保留最近7天的数据）
  Future<int> cleanOldData() async {
    final db = await database;
    final cutoffDate =
        DateTime.now().subtract(Duration(days: 7)).toIso8601String();

    // 清除旧的价格数据
    final deletedTickersCount = await db.delete(
      'tickers',
      where: 'created_at < ?',
      whereArgs: [cutoffDate],
    );

    // 清除旧的新闻数据（保留30天）
    final oldNewsDate =
        DateTime.now().subtract(Duration(days: 30)).toIso8601String();
    final deletedNewsCount = await db.delete(
      'news',
      where: 'published_at < ?',
      whereArgs: [oldNewsDate],
    );

    return deletedTickersCount + deletedNewsCount;
  }

  // 获取数据库大小
  Future<int> getDatabaseSize() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'crypto_data.db');
    final File dbFile = File(path);
    if (await dbFile.exists()) {
      return await dbFile.length();
    }
    return 0;
  }
}
