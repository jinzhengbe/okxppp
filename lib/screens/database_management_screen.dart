import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/influxdb_service.dart';
import '../services/postgres_service.dart';
import '../models/price_data.dart';
import '../models/trade_data.dart';
import '../models/sentiment_data.dart';
import '../services/crypto_data_collection_service.dart';
import '../services/database_management_service.dart';

class DatabaseManagementScreen extends StatefulWidget {
  const DatabaseManagementScreen({Key? key}) : super(key: key);

  @override
  State<DatabaseManagementScreen> createState() =>
      _DatabaseManagementScreenState();
}

class _DatabaseManagementScreenState extends State<DatabaseManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final InfluxDBService _influxDBService = InfluxDBService();
  final PostgresService _postgresService = PostgresService();
  final CryptoDataCollectionService _dataCollectionService =
      CryptoDataCollectionService();
  final DatabaseManagementService _dbManagementService =
      DatabaseManagementService();

  // 数据库状态
  bool _isDatabaseRunning = false;

  // 数据收集状态
  bool _isCollectingData = false;

  // 数据查询参数
  String _selectedSymbol = 'BTC-USDT';
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();

  // 查询结果
  List<PriceData> _priceData = [];
  List<TradeData> _tradeData = [];
  List<SentimentData> _sentimentData = [];

  // 加载状态
  bool _isLoadingPriceData = false;
  bool _isLoadingTradeData = false;
  bool _isLoadingSentimentData = false;

  // 可用的交易对
  final List<String> _availableSymbols = [
    'BTC-USDT',
    'ETH-USDT',
    'SOL-USDT',
    'XRP-USDT',
    'DOGE-USDT'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _checkDataCollectionStatus();
    _checkDatabaseStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 检查数据收集状态
  void _checkDataCollectionStatus() {
    // 这里应该从服务中获取实际状态
    setState(() {
      _isCollectingData = false;
    });
  }

  // 切换数据收集状态
  Future<void> _toggleDataCollection() async {
    setState(() {
      _isCollectingData = !_isCollectingData;
    });

    if (_isCollectingData) {
      await _dataCollectionService.startAllDataCollection();
    } else {
      _dataCollectionService.stopAllDataCollection();
    }
  }

  // 查询价格数据
  Future<void> _queryPriceData() async {
    setState(() {
      _isLoadingPriceData = true;
    });

    try {
      final data = await _influxDBService.queryPriceData(
        symbol: _selectedSymbol,
        start: _startDate,
        end: _endDate,
      );

      setState(() {
        _priceData = data;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('查询价格数据失败: $e')),
      );
    } finally {
      setState(() {
        _isLoadingPriceData = false;
      });
    }
  }

  // 查询交易数据
  Future<void> _queryTradeData() async {
    setState(() {
      _isLoadingTradeData = true;
    });

    try {
      final data = await _postgresService.queryTradeData(
        symbol: _selectedSymbol,
        start: _startDate,
        end: _endDate,
      );

      setState(() {
        _tradeData = data;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('查询交易数据失败: $e')),
      );
    } finally {
      setState(() {
        _isLoadingTradeData = false;
      });
    }
  }

  // 查询情绪数据
  Future<void> _querySentimentData() async {
    setState(() {
      _isLoadingSentimentData = true;
    });

    try {
      final data = await _postgresService.querySentimentData(
        symbol: _selectedSymbol.split('-')[0], // 只取币种部分，如BTC
        start: _startDate,
        end: _endDate,
      );

      setState(() {
        _sentimentData = data;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('查询情绪数据失败: $e')),
      );
    } finally {
      setState(() {
        _isLoadingSentimentData = false;
      });
    }
  }

  // 选择日期范围
  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  // 检查数据库状态
  Future<void> _checkDatabaseStatus() async {
    final isRunning = await _dbManagementService.checkDatabaseStatus();
    setState(() {
      _isDatabaseRunning = isRunning;
    });
  }

  // 启动数据库
  Future<void> _startDatabases() async {
    final result = await _dbManagementService.startDatabases();
    if (result) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('数据库启动成功')),
      );
      await _checkDatabaseStatus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('数据库启动失败，请检查Docker是否运行')),
      );
    }
  }

  // 停止数据库
  Future<void> _stopDatabases() async {
    final result = await _dbManagementService.stopDatabases();
    if (result) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('数据库停止成功')),
      );
      await _checkDatabaseStatus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('数据库停止失败')),
      );
    }
  }

  // 备份数据库
  Future<void> _backupDatabases() async {
    try {
      // 获取应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      final backupPath = '${directory.path}/backups';

      final result = await _dbManagementService.backupDatabases(backupPath);
      if (result) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('数据库备份成功，保存在: $backupPath')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('数据库备份失败')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('数据库备份失败: $e')),
      );
    }
  }

  // 导出数据
  Future<void> _exportData() async {
    try {
      // 获取应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      final exportPath = '${directory.path}/exports';

      final result = await _dbManagementService.exportData(
        _selectedSymbol,
        _startDate,
        _endDate,
        exportPath,
      );

      if (result) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('数据导出成功，保存在: $exportPath')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('数据导出失败')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('数据导出失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据库管理'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '价格数据'),
            Tab(text: '交易数据'),
            Tab(text: '情绪数据'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isCollectingData ? Icons.stop : Icons.play_arrow),
            tooltip: _isCollectingData ? '停止数据收集' : '开始数据收集',
            onPressed: _toggleDataCollection,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildPriceDataTab(),
          _buildTradeDataTab(),
          _buildSentimentDataTab(),
        ],
      ),
    );
  }

  // 构建概览标签页
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '数据库状态',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildStatusItem('InfluxDB', _isDatabaseRunning),
                  _buildStatusItem('PostgreSQL', _isDatabaseRunning),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _isDatabaseRunning ? null : _startDatabases,
                        child: const Text('启动数据库'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _isDatabaseRunning ? _stopDatabases : null,
                        child: const Text('停止数据库'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '数据收集状态',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildStatusItem('价格数据收集', _isCollectingData),
                  _buildStatusItem('订单簿数据收集', _isCollectingData),
                  _buildStatusItem('交易数据收集', _isCollectingData),
                  _buildStatusItem('情绪数据收集', _isCollectingData),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed:
                        _isDatabaseRunning ? _toggleDataCollection : null,
                    child: Text(_isCollectingData ? '停止所有数据收集' : '开始所有数据收集'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '数据库连接信息',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text('InfluxDB:'),
                  const Text('URL: http://localhost:8086'),
                  const Text('组织: crypto'),
                  const Text('存储桶: crypto_data'),
                  const SizedBox(height: 16),
                  const Text('PostgreSQL:'),
                  const Text('主机: localhost:5432'),
                  const Text('数据库: crypto_trading'),
                  const Text('用户: admin'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '数据管理操作',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _isDatabaseRunning ? _backupDatabases : null,
                        child: const Text('备份数据'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _isDatabaseRunning ? _exportData : null,
                        child: const Text('导出数据'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建状态项
  Widget _buildStatusItem(String title, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.cancel,
            color: isActive ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(title),
          const Spacer(),
          Text(isActive ? '活跃' : '停止'),
        ],
      ),
    );
  }

  // 构建价格数据标签页
  Widget _buildPriceDataTab() {
    return Column(
      children: [
        _buildQueryControls(_queryPriceData),
        Expanded(
          child: _isLoadingPriceData
              ? const Center(child: CircularProgressIndicator())
              : _priceData.isEmpty
                  ? const Center(child: Text('没有数据，请先查询'))
                  : _buildPriceDataList(),
        ),
      ],
    );
  }

  // 构建价格数据列表
  Widget _buildPriceDataList() {
    return ListView.builder(
      itemCount: _priceData.length,
      itemBuilder: (context, index) {
        final data = _priceData[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(
                '${data.symbol} - ${DateFormat('yyyy-MM-dd HH:mm').format(data.timestamp)}'),
            subtitle: Text(
                '开盘: ${data.open.toStringAsFixed(2)}, 收盘: ${data.close.toStringAsFixed(2)}, 最高: ${data.high.toStringAsFixed(2)}, 最低: ${data.low.toStringAsFixed(2)}'),
            trailing: Text('成交量: ${data.volume.toStringAsFixed(2)}'),
          ),
        );
      },
    );
  }

  // 构建交易数据标签页
  Widget _buildTradeDataTab() {
    return Column(
      children: [
        _buildQueryControls(_queryTradeData),
        Expanded(
          child: _isLoadingTradeData
              ? const Center(child: CircularProgressIndicator())
              : _tradeData.isEmpty
                  ? const Center(child: Text('没有数据，请先查询'))
                  : _buildTradeDataList(),
        ),
      ],
    );
  }

  // 构建交易数据列表
  Widget _buildTradeDataList() {
    return ListView.builder(
      itemCount: _tradeData.length,
      itemBuilder: (context, index) {
        final data = _tradeData[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(
                '${data.symbol} - ${DateFormat('yyyy-MM-dd HH:mm').format(data.timestamp)}'),
            subtitle: Text(
                '价格: ${data.price.toStringAsFixed(2)}, 数量: ${data.amount.toStringAsFixed(6)}, 方向: ${data.direction}'),
            trailing: Text('总价值: ${data.totalValue.toStringAsFixed(2)}'),
          ),
        );
      },
    );
  }

  // 构建情绪数据标签页
  Widget _buildSentimentDataTab() {
    return Column(
      children: [
        _buildQueryControls(_querySentimentData),
        Expanded(
          child: _isLoadingSentimentData
              ? const Center(child: CircularProgressIndicator())
              : _sentimentData.isEmpty
                  ? const Center(child: Text('没有数据，请先查询'))
                  : _buildSentimentDataList(),
        ),
      ],
    );
  }

  // 构建情绪数据列表
  Widget _buildSentimentDataList() {
    return ListView.builder(
      itemCount: _sentimentData.length,
      itemBuilder: (context, index) {
        final data = _sentimentData[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(
                '${data.symbol} - ${DateFormat('yyyy-MM-dd HH:mm').format(data.timestamp)}'),
            subtitle: Text(
                '来源: ${data.source}, 情绪分数: ${data.sentimentScore.toStringAsFixed(2)}, 提及次数: ${data.mentionCount}'),
            trailing: Icon(
              data.sentimentScore > 0.3
                  ? Icons.sentiment_satisfied
                  : data.sentimentScore < -0.3
                      ? Icons.sentiment_dissatisfied
                      : Icons.sentiment_neutral,
              color: data.sentimentScore > 0.3
                  ? Colors.green
                  : data.sentimentScore < -0.3
                      ? Colors.red
                      : Colors.grey,
            ),
          ),
        );
      },
    );
  }

  // 构建查询控件
  Widget _buildQueryControls(Function() onQuery) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: '交易对',
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedSymbol,
                  items: _availableSymbols.map((symbol) {
                    return DropdownMenuItem<String>(
                      value: symbol,
                      child: Text(symbol),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedSymbol = value;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _selectDateRange,
                child: const Text('选择日期范围'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '日期范围: ${DateFormat('yyyy-MM-dd').format(_startDate)} 至 ${DateFormat('yyyy-MM-dd').format(_endDate)}',
                ),
              ),
              ElevatedButton(
                onPressed: onQuery,
                child: const Text('查询'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
