import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/news.dart';
import '../services/news_service.dart';
import 'package:url_launcher/url_launcher.dart';

class NewsList extends StatefulWidget {
  final String? filterSymbol;
  final int maxItems;
  final bool showRelatedPrice;
  final bool autoRefresh;

  const NewsList({
    Key? key,
    this.filterSymbol,
    this.maxItems = 20,
    this.showRelatedPrice = true,
    this.autoRefresh = true,
  }) : super(key: key);

  @override
  State<NewsList> createState() => _NewsListState();
}

class _NewsListState extends State<NewsList> {
  final NewsService _newsService = NewsService();
  List<News> _newsList = [];
  bool _isLoading = true;
  String _errorMessage = '';
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadNews();

    // 如果启用了自动刷新，每5分钟刷新一次
    if (widget.autoRefresh) {
      Future.delayed(const Duration(minutes: 5), () {
        if (mounted) {
          _loadNews();
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NewsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterSymbol != widget.filterSymbol) {
      _loadNews();
    }
  }

  Future<void> _loadNews() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      List<News> news;
      if (widget.filterSymbol != null) {
        news = await _newsService.fetchNewsBySymbol(widget.filterSymbol!);
      } else {
        news = await _newsService.fetchAllNews();
      }

      if (news.length > widget.maxItems) {
        news = news.sublist(0, widget.maxItems);
      }

      setState(() {
        _newsList = news;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载新闻失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadNews,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_newsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '没有找到新闻',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNews,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _newsList.length,
        itemBuilder: (context, index) {
          final news = _newsList[index];
          return _buildNewsCard(context, news);
        },
      ),
    );
  }

  Widget _buildNewsCard(BuildContext context, News news) {
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

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: InkWell(
        onTap: () {
          _showNewsDetail(news);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showRelatedPrice &&
                  news.relatedSymbols.isNotEmpty) ...[
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
              const SizedBox(height: 8),
              Text(
                news.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                truncatedContent,
                style: const TextStyle(fontSize: 14),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNewsDetail(News news) {
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
                          '内容:',
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
                                final url = Uri.parse(news.url!);
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url);
                                }
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
}
