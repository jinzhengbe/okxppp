import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../api/okx_api.dart';

class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({Key? key}) : super(key: key);

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  final OkxApi _api = OkxApi();

  // 代理设置相关变量
  bool _useProxy = false;
  final TextEditingController _proxyHostController = TextEditingController();
  final TextEditingController _proxyPortController = TextEditingController();

  // 日志相关
  List<String> _logMessages = [];
  final ScrollController _logScrollController = ScrollController();

  // 网络状态
  bool _isRunningTest = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _loadProxySettings();
    _addLogMessage('网络设置页面已加载');
  }

  @override
  void dispose() {
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    super.dispose();
  }

  // 加载代理设置
  void _loadProxySettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useProxy = prefs.getBool('use_proxy') ?? false;
      _proxyHostController.text = prefs.getString('proxy_host') ?? '127.0.0.1';
      _proxyPortController.text = prefs.getString('proxy_port') ?? '7890';
    });

    if (_useProxy) {
      // 设置环境变量
      final proxyUrl =
          'http://${_proxyHostController.text}:${_proxyPortController.text}';
      Platform.environment['HTTP_PROXY'] = proxyUrl;
      Platform.environment['HTTPS_PROXY'] = proxyUrl;

      _addLogMessage('已加载代理设置: $proxyUrl');
    }
  }

  // 保存代理设置
  void _saveProxySettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_proxy', _useProxy);

    if (_useProxy) {
      await prefs.setString('proxy_host', _proxyHostController.text);
      await prefs.setString('proxy_port', _proxyPortController.text);

      // 设置环境变量
      final proxyUrl =
          'http://${_proxyHostController.text}:${_proxyPortController.text}';
      Platform.environment['HTTP_PROXY'] = proxyUrl;
      Platform.environment['HTTPS_PROXY'] = proxyUrl;

      _addLogMessage('已保存代理设置: $proxyUrl');
    } else {
      // 清除环境变量
      Platform.environment['HTTP_PROXY'] = '';
      Platform.environment['HTTPS_PROXY'] = '';

      _addLogMessage('已禁用代理');
    }
  }

  // 添加日志消息
  void _addLogMessage(String message) {
    setState(() {
      _logMessages.add(
        '${DateFormat('HH:mm:ss').format(DateTime.now())}: $message',
      );

      // 限制日志消息数量
      if (_logMessages.length > 100) {
        _logMessages.removeAt(0);
      }

      // 滚动到底部
      Future.delayed(Duration(milliseconds: 100), () {
        if (_logScrollController.hasClients) {
          _logScrollController.animateTo(
            _logScrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  // 测试代理连接
  void _testProxyConnection() async {
    if (!_useProxy) {
      _addLogMessage('请先启用代理');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请先启用代理设置'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final proxyHost = _proxyHostController.text;
    final proxyPort = int.tryParse(_proxyPortController.text) ?? 0;

    if (proxyHost.isEmpty || proxyPort <= 0) {
      _addLogMessage('代理设置无效');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('代理设置无效，请输入正确的服务器地址和端口'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _addLogMessage('测试代理连接: $proxyHost:$proxyPort');
    setState(() {
      _isRunningTest = true;
    });

    bool proxyConnected = false;
    bool okxConnected = false;
    String errorMessage = '';

    try {
      // 测试代理连接
      _addLogMessage('尝试连接到代理服务器...');
      final socket = await Socket.connect(proxyHost, proxyPort,
          timeout: const Duration(seconds: 3));
      _addLogMessage('代理连接成功');
      proxyConnected = true;
      socket.destroy();

      // 测试通过代理访问OKX
      _addLogMessage('测试通过代理访问OKX...');

      final client = HttpClient();
      client.findProxy = (uri) => 'PROXY $proxyHost:$proxyPort';
      client.connectionTimeout = const Duration(seconds: 5);
      client.badCertificateCallback = (cert, host, port) => true;

      try {
        final request = await client.getUrl(Uri.parse('https://www.okx.com'));
        final response = await request.close();

        _addLogMessage('通过代理访问OKX成功，状态码: ${response.statusCode}');
        okxConnected = true;
        client.close();
      } catch (e) {
        _addLogMessage('通过代理访问OKX失败: $e');
        errorMessage = '代理可连接，但无法访问OKX: ${e.toString().split('\n')[0]}';
        client.close();
      }

      // 显示测试结果
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              okxConnected ? '代理测试成功' : '代理测试部分成功',
              style: TextStyle(
                color: okxConnected ? Colors.green : Colors.orange,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('代理服务器: $proxyHost:$proxyPort'),
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      proxyConnected ? Icons.check_circle : Icons.error,
                      color: proxyConnected ? Colors.green : Colors.red,
                    ),
                    SizedBox(width: 8),
                    Text('代理服务器连接'),
                  ],
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      okxConnected ? Icons.check_circle : Icons.error,
                      color: okxConnected ? Colors.green : Colors.red,
                    ),
                    SizedBox(width: 8),
                    Text('通过代理访问OKX'),
                  ],
                ),
                if (errorMessage.isNotEmpty) ...[
                  SizedBox(height: 8),
                  Text(
                    errorMessage,
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('关闭'),
              ),
            ],
          );
        },
      );

      // 如果代理测试成功，更新环境变量
      if (proxyConnected) {
        final proxyUrl = 'http://$proxyHost:$proxyPort';
        Platform.environment['HTTP_PROXY'] = proxyUrl;
        Platform.environment['HTTPS_PROXY'] = proxyUrl;
        _addLogMessage('已更新代理环境变量: $proxyUrl');
        setState(() {
          _isConnected = okxConnected;
        });
      }
    } catch (e) {
      _addLogMessage('代理连接测试失败: $e');

      // 显示错误对话框
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('代理测试失败', style: TextStyle(color: Colors.red)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('无法连接到代理服务器: $proxyHost:$proxyPort'),
                SizedBox(height: 8),
                Text(
                  '错误信息: ${e.toString().split('\n')[0]}',
                  style: TextStyle(fontSize: 12),
                ),
                SizedBox(height: 16),
                Text('可能的原因:'),
                Text('1. 代理服务器未运行'),
                Text('2. 代理地址或端口错误'),
                Text('3. 代理服务器拒绝连接'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('关闭'),
              ),
            ],
          );
        },
      );
    } finally {
      setState(() {
        _isRunningTest = false;
      });
    }
  }

  // 测试直接连接
  void _testDirectConnection() async {
    _addLogMessage('测试直接连接到OKX...');
    setState(() {
      _isRunningTest = true;
    });

    try {
      // 测试REST API连接
      _addLogMessage('测试REST API连接...');
      final ticker = await _api.getTicker('BTC-USDT');
      _addLogMessage('REST API连接成功，当前价格: ${ticker.currentPrice}');
      setState(() {
        _isConnected = true;
      });

      // 显示成功对话框
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('连接测试成功', style: TextStyle(color: Colors.green)),
            content: Text('成功连接到OKX服务器，无需使用代理。'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('关闭'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      _addLogMessage('REST API连接失败: $e');
      setState(() {
        _isConnected = false;
      });

      // 显示错误对话框
      String errorMessage = '无法连接到OKX服务器';
      String suggestion = '建议配置代理服务器';
      IconData iconData = Icons.cloud_off;

      if (e.toString().contains('Operation not permitted')) {
        errorMessage = '系统权限问题: 连接被阻止';
        suggestion = '这是macOS的安全限制，建议配置代理或为应用签名';
        iconData = Icons.security;
      } else if (e.toString().contains('Connection refused')) {
        errorMessage = '连接被拒绝';
        suggestion = '服务器可能拒绝了连接请求';
        iconData = Icons.block;
      } else if (e.toString().contains('Connection timed out')) {
        errorMessage = '连接超时';
        suggestion = '网络可能不稳定或被防火墙阻止';
        iconData = Icons.timer_off;
      }

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('连接测试失败', style: TextStyle(color: Colors.red)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(iconData, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(child: Text(errorMessage)),
                  ],
                ),
                SizedBox(height: 16),
                Text(suggestion),
                SizedBox(height: 8),
                Text(
                  '错误详情: ${e.toString().split('\n')[0]}',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('关闭'),
              ),
              if (e.toString().contains('Operation not permitted'))
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _useProxy = true;
                    });
                    _saveProxySettings();
                  },
                  child: Text('启用代理'),
                ),
            ],
          );
        },
      );
    } finally {
      setState(() {
        _isRunningTest = false;
      });
    }
  }

  // 运行详细的网络诊断
  void _runNetworkDiagnostics() async {
    _addLogMessage('开始详细网络诊断...');
    setState(() {
      _isRunningTest = true;
    });

    // 测试DNS解析
    _addLogMessage('测试DNS解析...');
    final hosts = [
      'www.okx.com',
      'aws.okx.com',
      'wsaws.okx.com',
    ];

    for (final host in hosts) {
      try {
        final addresses = await InternetAddress.lookup(host);
        _addLogMessage(
            'DNS解析 $host 成功: ${addresses.map((a) => a.address).join(', ')}');
      } catch (e) {
        _addLogMessage('DNS解析 $host 失败: $e');
      }
    }

    // 测试HTTP连接
    _addLogMessage('测试HTTP连接...');
    final urls = [
      'https://www.okx.com',
      'https://aws.okx.com',
    ];

    for (final url in urls) {
      try {
        final httpClient = HttpClient();
        httpClient.connectionTimeout = const Duration(seconds: 5);

        final request = await httpClient.getUrl(Uri.parse(url));
        final response = await request.close();

        _addLogMessage('HTTP连接 $url 成功，状态码: ${response.statusCode}');
        httpClient.close();
      } catch (e) {
        _addLogMessage('HTTP连接 $url 失败: $e');
      }
    }

    // 测试WebSocket端口
    _addLogMessage('测试WebSocket端口...');
    final wsTests = [
      {'host': 'wsaws.okx.com', 'port': 8443},
      {'host': 'ws.okx.com', 'port': 8443},
    ];

    for (final test in wsTests) {
      try {
        _addLogMessage('尝试连接到 ${test['host']}:${test['port']}...');

        // 使用Socket API测试端口连接
        final socket = await Socket.connect(
          test['host'] as String,
          test['port'] as int,
          timeout: const Duration(seconds: 5),
        );

        _addLogMessage('Socket连接到 ${test['host']}:${test['port']} 成功');
        socket.destroy();
      } catch (e) {
        _addLogMessage('Socket连接到 ${test['host']}:${test['port']} 失败: $e');

        if (e.toString().contains('Operation not permitted')) {
          _addLogMessage('⚠️ 检测到系统权限问题，可能需要检查应用程序网络权限或使用VPN');
        } else if (e.toString().contains('Connection refused')) {
          _addLogMessage('⚠️ 连接被拒绝，服务器可能拒绝了连接请求');
        } else if (e.toString().contains('Connection timed out')) {
          _addLogMessage('⚠️ 连接超时，可能是网络问题或防火墙阻止');
        }
      }
    }

    // 提供解决建议
    _addLogMessage('诊断完成，建议:');
    _addLogMessage('1. 如果DNS解析成功但连接失败，可能是网络权限问题');
    _addLogMessage('2. 考虑使用代理服务器');
    _addLogMessage('3. 检查macOS的应用程序网络权限');
    _addLogMessage('4. 如果REST API工作但WebSocket不工作，建议使用REST API模式');

    setState(() {
      _isRunningTest = false;
    });
  }

  // 复制日志内容到剪贴板
  void _copyLogs() async {
    if (_logMessages.isEmpty) {
      // 如果没有日志，显示提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有日志可复制')),
      );
      return;
    }

    // 将所有日志合并为一个字符串
    final String logText = _logMessages.join('\n');

    // 复制到剪贴板
    await Clipboard.setData(ClipboardData(text: logText));

    // 显示成功提示
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('日志已复制到剪贴板')),
    );
  }

  // 清除日志
  void _clearLogs() {
    setState(() {
      _logMessages.clear();
    });
    _addLogMessage('日志已清除');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('网络设置'),
        actions: [
          // 连接状态指示器
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _isConnected ? '已连接' : '未连接',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isRunningTest
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在测试网络连接...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 连接测试卡片
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '连接测试',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: Icon(Icons.public),
                                  label: Text('测试直接连接'),
                                  onPressed: _testDirectConnection,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: Icon(Icons.network_check),
                                  label: Text('详细网络诊断'),
                                  onPressed: _runNetworkDiagnostics,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 16),

                  // 代理设置卡片
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '代理设置',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 16),

                          // 代理开关
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('使用代理'),
                              Switch(
                                value: _useProxy,
                                onChanged: (value) {
                                  setState(() {
                                    _useProxy = value;
                                  });
                                  _saveProxySettings();
                                },
                              ),
                            ],
                          ),

                          // 代理设置表单
                          if (_useProxy) ...[
                            TextField(
                              controller: _proxyHostController,
                              decoration: const InputDecoration(
                                labelText: '代理服务器地址',
                                hintText: '例如: 127.0.0.1',
                              ),
                              onChanged: (_) => _saveProxySettings(),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _proxyPortController,
                              decoration: const InputDecoration(
                                labelText: '代理服务器端口',
                                hintText: '例如: 7890',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => _saveProxySettings(),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: Icon(Icons.check_circle),
                              label: Text('测试代理连接'),
                              onPressed: _testProxyConnection,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 16),

                  // macOS系统权限解决方案卡片
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'macOS系统权限解决方案',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 16),
                          Text(
                            '如果您遇到"Operation not permitted"错误，这是macOS的安全限制。您可以尝试以下解决方案:',
                          ),
                          SizedBox(height: 8),
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.blue.withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '在终端中执行以下命令:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 8),
                                SelectableText(
                                  'sudo codesign --force --deep --sign - /Users/yijin/Desktop/bitcoin/okx_trading_app/build/macos/Build/Products/Debug/okx_trading_app.app',
                                  style: TextStyle(
                                      fontFamily: 'monospace', fontSize: 12),
                                ),
                                SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      icon: Icon(Icons.copy),
                                      label: Text('复制命令'),
                                      onPressed: () async {
                                        await Clipboard.setData(ClipboardData(
                                            text:
                                                'sudo codesign --force --deep --sign - /Users/yijin/Desktop/bitcoin/okx_trading_app/build/macos/Build/Products/Debug/okx_trading_app.app'));
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(content: Text('命令已复制到剪贴板')),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            '或者，您可以在系统偏好设置中允许网络连接:',
                          ),
                          SizedBox(height: 8),
                          Text(
                            '1. 打开系统偏好设置 > 安全性与隐私 > 防火墙\n'
                            '2. 点击"防火墙选项"\n'
                            '3. 确保"阻止所有传入连接"未被选中\n'
                            '4. 如果列表中有您的应用，确保它被设置为"允许传入连接"',
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 16),

                  // 日志卡片
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '网络日志',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.copy),
                                    tooltip: '复制日志',
                                    onPressed: _copyLogs,
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete),
                                    tooltip: '清除日志',
                                    onPressed: _clearLogs,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView.builder(
                              controller: _logScrollController,
                              padding: EdgeInsets.all(8),
                              itemCount: _logMessages.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2.0),
                                  child: Text(
                                    _logMessages[index],
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                );
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
  }
}
