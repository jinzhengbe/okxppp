import 'package:flutter/material.dart';
import '../widgets/news_list.dart';
import '../services/news_service.dart';
import '../models/news.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({Key? key}) : super(key: key);

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final NewsService _newsService = NewsService();
  String? _selectedSymbol;
  List<String> _availableSymbols = [];
  bool _isLoadingSymbols = true;
  List<News> _newsList = [];

  @override
  void initState() {
    super.initState();
    _loadAvailableSymbols();
  }

  Future<void> _loadAvailableSymbols() async {
    setState(() {
      _isLoadingSymbols = true;
    });

    try {
      // 获取所有新闻
      _newsList = await _newsService.fetchAllNews();

      // 提取所有相关的虚拟币符号
      final symbols = <String>{};
      for (var item in _newsList) {
        if (item.relatedSymbols.isNotEmpty) {
          for (var relation in item.relatedSymbols) {
            symbols.add(relation.symbol);
          }
        }
      }

      setState(() {
        _availableSymbols = symbols.toList()..sort();
        _isLoadingSymbols = false;
      });
    } catch (e) {
      print('加载虚拟币符号失败: $e');

      // 添加一些模拟数据，以便在出错时也能显示界面
      setState(() {
        _availableSymbols = ['BTC', 'ETH', 'SOL', 'DOGE', 'XRP'];
        _isLoadingSymbols = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('虚拟币新闻'),
        actions: [
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新新闻',
            onPressed: () {
              // 重新加载新闻和符号
              _loadAvailableSymbols();
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 筛选器
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Text('按虚拟币筛选:'),
                const SizedBox(width: 16),
                Expanded(
                  child: _isLoadingSymbols
                      ? const Center(child: CircularProgressIndicator())
                      : DropdownButton<String>(
                          isExpanded: true,
                          hint: const Text('所有新闻'),
                          value: _selectedSymbol,
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('所有新闻'),
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

          // 新闻列表
          Expanded(
            child: NewsList(
              filterSymbol: _selectedSymbol,
              maxItems: 100,
              showRelatedPrice: true,
              autoRefresh: true,
            ),
          ),
        ],
      ),
    );
  }
}
