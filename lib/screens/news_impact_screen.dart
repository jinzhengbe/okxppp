import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/news.dart';
import '../services/advanced_news_service.dart';
import '../widgets/news_list.dart';

class NewsImpactScreen extends StatefulWidget {
  const NewsImpactScreen({Key? key}) : super(key: key);

  @override
  State<NewsImpactScreen> createState() => _NewsImpactScreenState();
}

class _NewsImpactScreenState extends State<NewsImpactScreen> {
  final AdvancedNewsService _advancedNewsService = AdvancedNewsService();
  Map<String, List<Map<String, dynamic>>> _impactAnalysis = {};
  bool _isLoading = true;
  String? _selectedSymbol;
  List<String> _availableSymbols = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadImpactAnalysis();
  }

  Future<void> _loadImpactAnalysis() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 获取新闻影响分析
      final impactAnalysis =
          await _advancedNewsService.getAllNewsImpactAnalysis();

      setState(() {
        _impactAnalysis = impactAnalysis;
        _availableSymbols = impactAnalysis.keys.toList()..sort();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载新闻影响分析失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('虚拟币新闻影响分析'),
        actions: [
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新分析',
            onPressed: _loadImpactAnalysis,
          ),
          // 搜索按钮
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索新闻',
            onPressed: () {
              _showSearchDialog();
            },
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _startDailyNewsSearch();
        },
        tooltip: '执行每日新闻搜索',
        child: const Icon(Icons.search),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载新闻影响分析...'),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 48),
            SizedBox(height: 16),
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadImpactAnalysis,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_impactAnalysis.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, color: Colors.blue, size: 48),
            SizedBox(height: 16),
            Text(
              '没有找到新闻影响分析数据',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _startDailyNewsSearch();
              },
              child: const Text('执行新闻搜索'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 虚拟币选择器
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Text('选择虚拟币:'),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  hint: const Text('选择虚拟币'),
                  value: _selectedSymbol,
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('所有虚拟币'),
                    ),
                    ..._availableSymbols.map((symbol) {
                      return DropdownMenuItem<String>(
                        value: symbol,
                        child: Text(symbol),
                      );
                    }).toList(),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedSymbol = value;
                    });
                  },
                ),
              ),
            ],
          ),
        ),

        // 影响分析列表
        Expanded(
          child: _selectedSymbol == null
              ? _buildAllSymbolsImpactList()
              : _buildSingleSymbolImpactList(_selectedSymbol!),
        ),
      ],
    );
  }

  Widget _buildAllSymbolsImpactList() {
    // 按影响分数排序的所有新闻
    List<Map<String, dynamic>> allImpactNews = [];

    for (var symbolNews in _impactAnalysis.values) {
      allImpactNews.addAll(symbolNews);
    }

    // 按影响分数的绝对值排序
    allImpactNews.sort((a, b) {
      return (b['impact_score'] as double)
          .abs()
          .compareTo((a['impact_score'] as double).abs());
    });

    return ListView.builder(
      itemCount: allImpactNews.length,
      itemBuilder: (context, index) {
        final item = allImpactNews[index];
        final news = item['news'] as News;
        final score = item['impact_score'] as double;
        final sentiment = item['sentiment'] as String;

        return _buildImpactNewsCard(news, score, sentiment);
      },
    );
  }

  Widget _buildSingleSymbolImpactList(String symbol) {
    final symbolNews = _impactAnalysis[symbol] ?? [];

    if (symbolNews.isEmpty) {
      return Center(
        child: Text('没有找到关于 $symbol 的新闻影响分析'),
      );
    }

    return ListView.builder(
      itemCount: symbolNews.length,
      itemBuilder: (context, index) {
        final item = symbolNews[index];
        final news = item['news'] as News;
        final score = item['impact_score'] as double;
        final sentiment = item['sentiment'] as String;

        return _buildImpactNewsCard(news, score, sentiment);
      },
    );
  }

  Widget _buildImpactNewsCard(News news, double score, String sentiment) {
    // 解析日期
    DateTime publishDate;
    try {
      publishDate = DateTime.parse(news.publishedAt);
    } catch (e) {
      publishDate = DateTime.now();
    }

    // 格式化日期
    final formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(publishDate);

    // 截断内容
    final truncatedContent = news.content.length > 150
        ? '${news.content.substring(0, 150)}...'
        : news.content;

    // 根据情绪确定颜色
    Color sentimentColor;
    IconData sentimentIcon;

    if (sentiment == 'positive') {
      sentimentColor = Colors.green;
      sentimentIcon = Icons.trending_up;
    } else if (sentiment == 'negative') {
      sentimentColor = Colors.red;
      sentimentIcon = Icons.trending_down;
    } else {
      sentimentColor = Colors.grey;
      sentimentIcon = Icons.trending_flat;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: InkWell(
        onTap: () {
          _showNewsDetail(news, score, sentiment);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 来源标签
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getSourceColor(news.source),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      news.source,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 日期
                  Text(
                    formattedDate,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  // 影响分数
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: sentimentColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: sentimentColor),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          sentimentIcon,
                          color: sentimentColor,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          score.abs().toStringAsFixed(2),
                          style: TextStyle(
                            color: sentimentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 标题
              Text(
                news.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              // 内容预览
              Text(
                truncatedContent,
                style: const TextStyle(fontSize: 14),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              // 相关虚拟币
              if (news.relatedSymbols.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: news.relatedSymbols.map((relation) {
                    return Chip(
                      label: Text(
                        relation.priceAtPublish != null
                            ? '${relation.symbol}: ${relation.priceAtPublish}'
                            : relation.symbol,
                      ),
                      backgroundColor: Colors.grey[200],
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showNewsDetail(News news, double score, String sentiment) {
    // 根据情绪确定颜色
    Color sentimentColor;
    String sentimentText;
    IconData sentimentIcon;

    if (sentiment == 'positive') {
      sentimentColor = Colors.green;
      sentimentText = '积极';
      sentimentIcon = Icons.trending_up;
    } else if (sentiment == 'negative') {
      sentimentColor = Colors.red;
      sentimentText = '消极';
      sentimentIcon = Icons.trending_down;
    } else {
      sentimentColor = Colors.grey;
      sentimentText = '中性';
      sentimentIcon = Icons.trending_flat;
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(
              maxWidth: 800,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              children: [
                // 标题栏
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          news.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // 内容区域
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 来源和日期
                        Row(
                          children: [
                            Text(
                              '来源: ${news.source}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '发布日期: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(news.publishedAt))}',
                              style: TextStyle(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 影响分析
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: sentimentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: sentimentColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    sentimentIcon,
                                    color: sentimentColor,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '影响分析',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '情绪倾向: $sentimentText',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '影响分数: ${score.abs().toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '该新闻可能对相关虚拟币价格产生${sentiment == 'positive' ? '正面' : (sentiment == 'negative' ? '负面' : '中性')}影响。',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 相关虚拟币
                        if (news.relatedSymbols.isNotEmpty) ...[
                          const Text(
                            '相关虚拟币:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: news.relatedSymbols.map((relation) {
                              return Chip(
                                label: Text(
                                  relation.priceAtPublish != null
                                      ? '${relation.symbol}: ${relation.priceAtPublish}'
                                      : relation.symbol,
                                ),
                                backgroundColor: Colors.blue[100],
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],
                        // 内容
                        const Text(
                          '新闻内容:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(news.content),
                        const SizedBox(height: 16),
                        // 原文链接
                        if (news.url != null && news.url!.isNotEmpty)
                          Center(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.link),
                              label: const Text('查看原文'),
                              onPressed: () async {
                                // 使用url_launcher打开链接
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getSourceColor(String source) {
    if (source.contains('OKX官方公告') || source.contains('OKX博客')) {
      return Colors.blue;
    } else if (source.contains('Google')) {
      return Colors.green;
    } else if (source.contains('CoinMarketCap')) {
      return Colors.orange;
    } else if (source.contains('DarkWeb')) {
      return Colors.purple;
    } else {
      return Colors.grey;
    }
  }

  void _showSearchDialog() {
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('搜索新闻'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入搜索关键词',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) {
              searchQuery = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (searchQuery.isNotEmpty) {
                  _searchNews(searchQuery);
                }
              },
              child: const Text('搜索'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _searchNews(String query) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 这里可以实现搜索功能，例如调用Google搜索API
      // 暂时使用模拟数据
      await Future.delayed(Duration(seconds: 2));

      setState(() {
        _isLoading = false;
      });

      // 显示搜索结果
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('搜索功能尚未实现'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '搜索失败: $e';
      });
    }
  }

  Future<void> _startDailyNewsSearch() async {
    // 显示进度对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('执行每日新闻搜索'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在搜索虚拟币相关新闻，这可能需要几分钟时间...'),
            ],
          ),
        );
      },
    );

    try {
      // 执行每日新闻搜索
      final newsList = await _advancedNewsService.performDailyNewsSearch();

      // 关闭进度对话框
      Navigator.of(context).pop();

      // 重新加载影响分析
      await _loadImpactAnalysis();

      // 显示结果
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功获取${newsList.length}条新闻'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // 关闭进度对话框
      Navigator.of(context).pop();

      // 显示错误
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('新闻搜索失败: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}
