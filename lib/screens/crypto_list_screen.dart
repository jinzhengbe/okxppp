import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/okx_api.dart';
import '../models/ticker.dart';
import '../widgets/chart_widget.dart';

class CryptoListScreen extends StatefulWidget {
  const CryptoListScreen({Key? key}) : super(key: key);

  @override
  State<CryptoListScreen> createState() => _CryptoListScreenState();
}

class _CryptoListScreenState extends State<CryptoListScreen> {
  final OkxApi _api = OkxApi();

  // 所有交易对列表
  List<Map<String, dynamic>> _instruments = [];

  // 所有交易对的行情数据
  Map<String, Ticker> _tickers = {};

  // 选中的交易对
  Set<String> _selectedSymbols = {};

  // 搜索关键词
  String _searchQuery = '';

  // 是否正在加载
  bool _isLoading = true;

  // 是否显示USDT交易对
  bool _showUsdtOnly = true;

  // 轮询定时器
  Timer? _pollingTimer;

  // 选中交易对的历史数据
  Map<String, List<Ticker>> _tickerHistory = {};

  @override
  void initState() {
    super.initState();
    _loadInstruments();
    _startPolling();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  // 加载所有交易对
  Future<void> _loadInstruments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final instruments = await _api.getAllInstruments();
      setState(() {
        // 按交易量排序（如果有交易量数据）
        _instruments = instruments;
        _isLoading = false;
      });

      // 初始选择BTC-USDT
      _selectedSymbols.add('BTC-USDT');

      // 获取初始行情数据
      _fetchTickers();
    } catch (e) {
      print('加载交易对失败: $e');
      setState(() {
        _isLoading = false;
      });

      // 显示错误提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('加载交易对失败: ${e.toString().split('\n')[0]}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 开始轮询获取行情数据
  void _startPolling() {
    // 取消现有的轮询定时器
    _pollingTimer?.cancel();

    // 设置新的轮询定时器，每2秒获取一次行情
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _fetchTickers();
    });
  }

  // 停止轮询
  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // 获取行情数据
  Future<void> _fetchTickers() async {
    if (_instruments.isEmpty) return;

    try {
      // 获取所有USDT交易对的行情
      final symbols = _showUsdtOnly
          ? _instruments
              .where((i) => i['instId'].toString().endsWith('-USDT'))
              .map((i) => i['instId'].toString())
              .toList()
          : _instruments.map((i) => i['instId'].toString()).toList();

      // 如果交易对太多，只获取前50个
      final limitedSymbols = symbols.take(50).toList();

      final tickers = await _api.getMultipleTickers(limitedSymbols);

      setState(() {
        // 更新行情数据
        for (final ticker in tickers) {
          _tickers[ticker.symbol] = ticker;

          // 更新选中交易对的历史数据
          if (_selectedSymbols.contains(ticker.symbol)) {
            if (!_tickerHistory.containsKey(ticker.symbol)) {
              _tickerHistory[ticker.symbol] = [];
            }

            _tickerHistory[ticker.symbol]!.add(ticker);

            // 限制历史数据长度
            if (_tickerHistory[ticker.symbol]!.length > 100) {
              _tickerHistory[ticker.symbol]!.removeAt(0);
            }
          }
        }
      });
    } catch (e) {
      print('获取行情数据失败: $e');
    }
  }

  // 切换交易对选择状态
  void _toggleSymbolSelection(String symbol) {
    setState(() {
      if (_selectedSymbols.contains(symbol)) {
        _selectedSymbols.remove(symbol);
        _tickerHistory.remove(symbol);
      } else {
        _selectedSymbols.add(symbol);
      }
    });
  }

  // 构建交易对列表
  Widget _buildCryptoList() {
    // 过滤交易对
    final filteredInstruments = _instruments.where((instrument) {
      final symbol = instrument['instId'].toString();
      final baseCcy = instrument['baseCcy'].toString();

      // 根据搜索关键词过滤
      final matchesSearch = _searchQuery.isEmpty ||
          symbol.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          baseCcy.toLowerCase().contains(_searchQuery.toLowerCase());

      // 根据USDT过滤
      final matchesUsdt = !_showUsdtOnly || symbol.endsWith('-USDT');

      return matchesSearch && matchesUsdt;
    }).toList();

    // 按价格变化百分比排序
    filteredInstruments.sort((a, b) {
      final symbolA = a['instId'].toString();
      final symbolB = b['instId'].toString();

      final tickerA = _tickers[symbolA];
      final tickerB = _tickers[symbolB];

      if (tickerA == null && tickerB == null) return 0;
      if (tickerA == null) return 1;
      if (tickerB == null) return -1;

      // 按价格变化百分比降序排序
      return tickerB.changePercentage.compareTo(tickerA.changePercentage);
    });

    return ListView.builder(
      itemCount: filteredInstruments.length,
      itemBuilder: (context, index) {
        final instrument = filteredInstruments[index];
        final symbol = instrument['instId'].toString();
        final baseCcy = instrument['baseCcy'].toString();
        final ticker = _tickers[symbol];

        // 价格变化百分比
        final changePercentage = ticker?.changePercentage ?? 0.0;
        final isPositive = changePercentage >= 0;

        return ListTile(
          title: Row(
            children: [
              // 选择框
              Checkbox(
                value: _selectedSymbols.contains(symbol),
                onChanged: (_) => _toggleSymbolSelection(symbol),
              ),
              // 币种名称
              Text(
                baseCcy,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8),
              // 交易对
              Text(
                symbol,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          trailing: ticker != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 价格
                    Text(
                      NumberFormat.currency(
                        symbol: '',
                        decimalDigits: ticker.currentPrice < 1 ? 6 : 2,
                      ).format(ticker.currentPrice),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // 价格变化百分比
                    Text(
                      '${isPositive ? '+' : ''}${changePercentage.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: isPositive ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              : CircularProgressIndicator(
                  strokeWidth: 2,
                ),
          onTap: () => _toggleSymbolSelection(symbol),
        );
      },
    );
  }

  // 构建图表区域
  Widget _buildChartArea() {
    if (_selectedSymbols.isEmpty) {
      return Center(
        child: Text('请选择至少一个交易对'),
      );
    }

    // 创建多个图表
    return ListView(
      children: _selectedSymbols.map((symbol) {
        final history = _tickerHistory[symbol] ?? [];

        return Card(
          margin: EdgeInsets.all(8),
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题和关闭按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      symbol,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => _toggleSymbolSelection(symbol),
                      iconSize: 16,
                    ),
                  ],
                ),
                // 价格信息
                if (_tickers.containsKey(symbol)) ...[
                  Row(
                    children: [
                      Text(
                        '当前价格: ${NumberFormat.currency(
                          symbol: '',
                          decimalDigits:
                              _tickers[symbol]!.currentPrice < 1 ? 6 : 2,
                        ).format(_tickers[symbol]!.currentPrice)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 16),
                      Text(
                        '24h变化: ${_tickers[symbol]!.changePercentage >= 0 ? '+' : ''}${_tickers[symbol]!.changePercentage.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: _tickers[symbol]!.changePercentage >= 0
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
                // 图表
                Container(
                  height: 200,
                  child: history.length > 1
                      ? ChartWidget(tickerHistory: history)
                      : Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('虚拟货币列表'),
        actions: [
          // 切换USDT交易对显示
          IconButton(
            icon: Icon(_showUsdtOnly ? Icons.attach_money : Icons.money_off),
            tooltip: _showUsdtOnly ? '显示所有交易对' : '只显示USDT交易对',
            onPressed: () {
              setState(() {
                _showUsdtOnly = !_showUsdtOnly;
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 搜索框
                Padding(
                  padding: EdgeInsets.all(8),
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: '搜索虚拟货币',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                // 选中的交易对数量
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '已选择: ${_selectedSymbols.length} 个交易对',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_selectedSymbols.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedSymbols.clear();
                              _tickerHistory.clear();
                            });
                          },
                          child: Text('清除所有'),
                        ),
                    ],
                  ),
                ),
                // 分割线
                Divider(),
                // 内容区域
                Expanded(
                  child: Row(
                    children: [
                      // 左侧列表
                      Expanded(
                        flex: 2,
                        child: _buildCryptoList(),
                      ),
                      // 分割线
                      VerticalDivider(),
                      // 右侧图表
                      Expanded(
                        flex: 3,
                        child: _buildChartArea(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
